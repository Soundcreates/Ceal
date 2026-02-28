/**
 * AfterMath Backend — SOS routes.
 *
 * POST /sos/ingest       — Receive & store an SOS event from mobile
 * POST /sos/acknowledge  — Acknowledge an active SOS
 * GET  /sos/active       — Fetch all active/relayed SOS events
 */

import { Router, type Request, type Response } from 'express';
import { sosIngestSchema, sosAckSchema } from '../models/sos-event.js';
import { SosRepository } from '../db/sos-repository.js';
import { UserRepository } from '../db/user-repository.js';
import { startEscalationTimer, cancelEscalationTimer } from '../services/escalation.js';
import { sendContactSms } from '../services/twilio.js';
import { optionalAuth } from '../middleware/auth.js';
import { logger } from '../logger.js';
import type { Pool } from 'pg';

// Helper — pull the correlated request ID injected by the app-level middleware.
const rid = (req: Request): string =>
  (req as Request & { reqId?: string }).reqId ?? 'no-rid';

export function createSosRouter(pool: Pool): Router {
  const router = Router();
  const repo = new SosRepository(pool);
  const userRepo = new UserRepository(pool);

  // -----------------------------------------------------------------------
  // POST /sos/ingest
  // -----------------------------------------------------------------------
  router.post('/ingest', optionalAuth, async (req: Request, res: Response) => {
    const reqId = rid(req);
    try {
      logger.debug('SOS ingest received', {
        reqId,
        bodyKeys: Object.keys(req.body ?? {}),
        contentLength: req.headers['content-length'] ?? 'unknown',
        caller: req.ip,
      });

      const parsed = sosIngestSchema.safeParse(req.body);
      if (!parsed.success) {
        const fieldErrors = parsed.error.flatten().fieldErrors;
        logger.warn('SOS ingest validation failed', { reqId, fieldErrors, body: req.body });
        res.status(400).json({
          error: 'Invalid SOS payload',
          details: fieldErrors,
        });
        return;
      }

      const data = parsed.data;
      logger.debug('SOS ingest payload parsed', {
        reqId,
        id: data.id,
        bleUid: data.bleUid,
        flags: data.flags,
        sequence: data.sequence,
        status: data.status,
        relayHops: data.relayHops,
        ts: data.timestamp,
        hasMessage: data.message !== undefined && data.message !== null,
      });

      // Resolve victim profile FIRST so we can store userId in the event
      const bleUidHex = data.bleUid.toLowerCase();
      const profile = await userRepo.findFullProfileByBleUid(bleUidHex);

      const t0 = Date.now();
      const event = await repo.upsert({
        id: data.id,
        bleUid: data.bleUid,
        flags: data.flags,
        sequence: data.sequence,
        receiverLat: data.receiverLocation?.lat,
        receiverLon: data.receiverLocation?.lon,
        rssi: data.rssi,
        userId: profile?.user.id,
        timestamp: data.timestamp,
        status: data.status,
        relayHops: data.relayHops,
        message: data.message,
      });
      const dbMs = Date.now() - t0;

      // Fire distress SMS to each emergency contact immediately (non-blocking)
      if (profile && profile.contacts.length > 0) {
        const lat = event.receiverLat ?? 0;
        const lon = event.receiverLon ?? 0;
        void Promise.allSettled(
          profile.contacts
            .filter((c) => c.phone)
            .map((c) =>
              sendContactSms({
                to: c.phone!,
                victimName: profile.user.name,
                sosId: event.id,
                latitude: lat,
                longitude: lon,
                timestamp: event.timestamp,
                message: event.message,
              }),
            ),
        ).then((results) => {
          const sent = results.filter((r) => r.status === 'fulfilled' && r.value).length;
          logger.info('Contact SMS dispatched', { reqId, id: event.id, sent, total: results.length });
        });
      }

      // Start escalation timer (operator SMS fallback if not acknowledged in 30s)
      if (event.status === 'active' || event.status === 'relayed') {
        startEscalationTimer(
          event.id,
          event.receiverLat ?? 0,
          event.receiverLon ?? 0,
          event.timestamp,
          event.message,
          repo,
        );
        logger.info('SOS escalation timer started', { reqId, id: event.id });
      }

      logger.info('SOS ingested OK', {
        reqId,
        id: event.id,
        bleUid: event.bleUid,
        status: event.status,
        relayHops: event.relayHops,
        receiverLat: event.receiverLat,
        receiverLon: event.receiverLon,
        dbMs,
      });
      res.status(201).json(event);
    } catch (err) {
      logger.error('SOS ingest unhandled error', {
        reqId,
        message: (err as Error).message,
        stack: (err as Error).stack,
      });
      res.status(500).json({ error: 'Internal server error' });
    }
  });

  // -----------------------------------------------------------------------
  // POST /sos/acknowledge
  // -----------------------------------------------------------------------
  router.post('/acknowledge', optionalAuth, async (req: Request, res: Response) => {
    const reqId = rid(req);
    try {
      const parsed = sosAckSchema.safeParse(req.body);
      if (!parsed.success) {
        const fieldErrors = parsed.error.flatten().fieldErrors;
        logger.warn('SOS ack validation failed', { reqId, fieldErrors });
        res.status(400).json({
          error: 'Invalid acknowledge payload',
          details: fieldErrors,
        });
        return;
      }

      const { id } = parsed.data;
      logger.debug('SOS ack request', { reqId, id });

      const t0 = Date.now();
      const event = await repo.acknowledge(id);
      const dbMs = Date.now() - t0;

      if (!event) {
        logger.warn('SOS ack — event not found or already resolved', { reqId, id, dbMs });
        res.status(404).json({ error: 'SOS event not found or already resolved' });
        return;
      }

      // Cancel escalation timer since it's now acknowledged
      cancelEscalationTimer(event.id);

      logger.info('SOS acknowledged OK', { reqId, id: event.id, dbMs });
      res.status(200).json(event);
    } catch (err) {
      logger.error('SOS acknowledge unhandled error', {
        reqId,
        message: (err as Error).message,
        stack: (err as Error).stack,
      });
      res.status(500).json({ error: 'Internal server error' });
    }
  });

  // -----------------------------------------------------------------------
  // GET /sos/active
  // -----------------------------------------------------------------------
  router.get('/active', optionalAuth, async (req: Request, res: Response) => {
    const reqId = rid(req);
    try {
      const t0 = Date.now();
      const events = await repo.findActive();
      const dbMs = Date.now() - t0;
      logger.info('Active SOS events fetched', { reqId, count: events.length, dbMs });
      res.status(200).json(events);
    } catch (err) {
      logger.error('Fetch active SOS events error', {
        reqId,
        message: (err as Error).message,
        stack: (err as Error).stack,
      });
      res.status(500).json({ error: 'Internal server error' });
    }
  });

  return router;
}
