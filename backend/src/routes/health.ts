/**
 * CEAL Backend — Health check route.
 */

import { Router, type Request, type Response } from 'express';
import type { Pool } from 'pg';
import { logger } from '../logger.js';

export function createHealthRouter(pool: Pool): Router {
  const router = Router();

  router.get('/', async (req: Request, res: Response) => {
    const t0 = Date.now();
    try {
      await pool.query('SELECT 1');
      const pingMs = Date.now() - t0;
      logger.info('Health check OK', { dbPingMs: pingMs });
      res.status(200).json({ status: 'ok', timestamp: new Date().toISOString(), dbPingMs: pingMs });
    } catch (err) {
      const pingMs = Date.now() - t0;
      logger.error('Health check FAILED — DB unreachable', {
        message: (err as Error).message,
        pingMs,
      });
      res.status(503).json({
        status: 'unhealthy',
        timestamp: new Date().toISOString(),
        dbPingMs: pingMs,
      });
    }
  });

  return router;
}
