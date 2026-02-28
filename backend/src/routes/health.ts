/**
 * AfterMath Backend — Health check route.
 */

import { Router, type Request, type Response } from 'express';
import type { Pool } from 'pg';

export function createHealthRouter(pool: Pool): Router {
  const router = Router();

  router.get('/', async (_req: Request, res: Response) => {
    try {
      await pool.query('SELECT 1');
      res.status(200).json({ status: 'ok', timestamp: new Date().toISOString() });
    } catch {
      res.status(503).json({ status: 'unhealthy', timestamp: new Date().toISOString() });
    }
  });

  return router;
}
