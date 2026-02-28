/**
 * CEAL Backend — SOS routes.
 *
 * POST /sos/ingest                — Receive & store an SOS event from mobile
 * POST /sos/acknowledge           — Acknowledge an active SOS
 * GET  /sos/active                — Fetch all active/relayed SOS events
 * GET  /sos/victim-profile/:bleUid — Look up victim profile by BLE UID
 */

import { Router, type Request, type Response } from 'express';
import { sosIngestSchema, sosAckSchema, extractSosType } from '../models/sos-event.js';
import { SosRepository } from '../db/sos-repository.js';
import { UserRepository } from '../db/user-repository.js';
import { startEscalationTimer, cancelEscalationTimer } from '../services/escalation.js';
import { sendContactSms, sendEscalationSms } from '../services/twilio.js';
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

      // Fire distress SMS to all emergency contacts + escalation number immediately (non-blocking)
      const lat = event.receiverLat ?? 0;
      const lon = event.receiverLon ?? 0;
      const contactsToNotify = profile?.contacts.filter((c) => c.phone) ?? [];

      void Promise.allSettled([
        // Emergency contacts
        ...contactsToNotify.map((c) =>
          sendContactSms({
            to: c.phone!,
            victimName: profile!.user.name,
            sosId: event.id,
            latitude: lat,
            longitude: lon,
            timestamp: event.timestamp,
            message: `[${extractSosType(data.flags)}] ${event.message ?? ''}`.trim(),
          }),
        ),
        // Escalation operator — immediate alert
        sendEscalationSms({
          sosId: event.id,
          latitude: lat,
          longitude: lon,
          timestamp: event.timestamp,
          message: `[${extractSosType(data.flags)}] ${event.message ?? ''}`.trim(),
          victimName: profile?.user.name ?? null,
          contactsNotified: contactsToNotify.length,
          isReminder: false,
        }),
      ]).then((results) => {
        const sent = results.filter((r) => r.status === 'fulfilled' && r.value).length;
        logger.info('SMS dispatched', {
          reqId,
          id: event.id,
          total: results.length,
          sent,
          contacts: contactsToNotify.length,
        });
      });

      // Start 30s timer — logs if SOS remains unacknowledged (no extra SMS)
      if (event.status === 'active' || event.status === 'relayed') {
        startEscalationTimer(event.id, repo);
        logger.info('SOS escalation timer started', { reqId, id: event.id });
      }

      // Extract SOS type label from flags.
      const sosType = extractSosType(event.flags ?? data.flags);

      logger.info('SOS ingested OK', {
        reqId,
        id: event.id,
        bleUid: event.bleUid,
        status: event.status,
        sosType,
        relayHops: event.relayHops,
        receiverLat: event.receiverLat,
        receiverLon: event.receiverLon,
        dbMs,
      });
      res.status(201).json({ ...event, sosType });
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
      // Enrich each event with sosType label.
      const enriched = events.map(e => ({
        ...e,
        sosType: extractSosType(e.flags ?? 0),
      }));
      logger.info('Active SOS events fetched', { reqId, count: events.length, dbMs });
      res.status(200).json(enriched);
    } catch (err) {
      logger.error('Fetch active SOS events error', {
        reqId,
        message: (err as Error).message,
        stack: (err as Error).stack,
      });
      res.status(500).json({ error: 'Internal server error' });
    }
  });

  // -----------------------------------------------------------------------
  // GET /sos/victim-profile/:bleUid — Resolve victim identity from BLE UID
  // -----------------------------------------------------------------------
  router.get('/victim-profile/:bleUid', optionalAuth, async (req: Request, res: Response) => {
    const reqId = rid(req);
    const bleUidHex = String(req.params.bleUid ?? '').toLowerCase().replace(/[^0-9a-f]/g, '');
    try {
      if (bleUidHex.length !== 12) {
        res.status(400).json({ error: 'BLE UID must be exactly 12 hex characters' });
        return;
      }

      const t0 = Date.now();
      const profile = await userRepo.findFullProfileByBleUid(bleUidHex);
      const dbMs = Date.now() - t0;

      if (!profile) {
        logger.info('Victim profile lookup — no user for UID', { reqId, bleUid: bleUidHex, dbMs });
        res.status(404).json({ error: 'No registered user for this BLE UID' });
        return;
      }

      const { user, contacts, medical } = profile;
      logger.info('Victim profile resolved', {
        reqId,
        bleUid: bleUidHex,
        userId: user.id,
        contactsCount: contacts.length,
        hasMedical: medical !== null,
        dbMs,
      });

      res.status(200).json({
        user: {
          id: user.id,
          name: user.name,
          phone: user.phone,
          language: user.language,
        },
        contacts: contacts.map((c) => ({
          name: c.name,
          phone: c.phone,
          priority: c.priority,
        })),
        medical: medical
          ? {
            bloodGroup: medical.bloodGroup,
            allergies: medical.allergies,
            conditions: medical.conditions,
          }
          : null,
      });
    } catch (err) {
      logger.error('Victim profile lookup error', {
        reqId,
        bleUid: bleUidHex,
        message: (err as Error).message,
        stack: (err as Error).stack,
      });
      res.status(500).json({ error: 'Internal server error' });
    }
  });

  return router;
}
