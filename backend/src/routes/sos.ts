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
import { startEscalationTimer, cancelEscalationTimer } from '../services/escalation.js';
import { optionalAuth } from '../middleware/auth.js';
import { logger } from '../logger.js';
import type { Pool } from 'pg';

export function createSosRouter(pool: Pool): Router {
  const router = Router();
  const repo = new SosRepository(pool);

  // -----------------------------------------------------------------------
  // POST /sos/ingest
  // -----------------------------------------------------------------------
  router.post('/ingest', optionalAuth, async (req: Request, res: Response) => {
    try {
      const parsed = sosIngestSchema.safeParse(req.body);
      if (!parsed.success) {
        res.status(400).json({
          error: 'Invalid SOS payload',
          details: parsed.error.flatten().fieldErrors,
        });
        return;
      }

      const data = parsed.data;
      const event = await repo.upsert({
        id: data.id,
        deviceIdHash: data.deviceIdHash,
        latitude: data.latitude,
        longitude: data.longitude,
        timestamp: data.timestamp,
        status: data.status,
        relayHops: data.relayHops,
        message: data.message,
      });

      // Start escalation timer (SMS fallback if not acknowledged in 30s)
      if (event.status === 'active' || event.status === 'relayed') {
        startEscalationTimer(
          event.id,
          event.latitude,
          event.longitude,
          event.timestamp,
          event.message,
          repo,
        );
      }

      logger.info(`SOS ingested: ${event.id} [${event.status}]`);
      res.status(201).json(event);
    } catch (err) {
      logger.error('SOS ingest error', err);
      res.status(500).json({ error: 'Internal server error' });
    }
  });

  // -----------------------------------------------------------------------
  // POST /sos/acknowledge
  // -----------------------------------------------------------------------
  router.post('/acknowledge', optionalAuth, async (req: Request, res: Response) => {
    try {
      const parsed = sosAckSchema.safeParse(req.body);
      if (!parsed.success) {
        res.status(400).json({
          error: 'Invalid acknowledge payload',
          details: parsed.error.flatten().fieldErrors,
        });
        return;
      }

      const event = await repo.acknowledge(parsed.data.id);
      if (!event) {
        res.status(404).json({ error: 'SOS event not found or already resolved' });
        return;
      }

      // Cancel escalation timer since it's now acknowledged
      cancelEscalationTimer(event.id);

      logger.info(`SOS acknowledged: ${event.id}`);
      res.status(200).json(event);
    } catch (err) {
      logger.error('SOS acknowledge error', err);
      res.status(500).json({ error: 'Internal server error' });
    }
  });

  // -----------------------------------------------------------------------
  // GET /sos/active
  // -----------------------------------------------------------------------
  router.get('/active', optionalAuth, async (_req: Request, res: Response) => {
    try {
      const events = await repo.findActive();
      res.status(200).json(events);
    } catch (err) {
      logger.error('Fetch active events error', err);
      res.status(500).json({ error: 'Internal server error' });
    }
  });

  return router;
}
