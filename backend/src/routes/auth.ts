/**
 * CEAL Backend — Auth routes (token generation for testing/admin).
 */

import { Router, type Request, type Response } from 'express';
import { z } from 'zod';
import { signToken } from '../middleware/auth.js';
import { logger } from '../logger.js';

const rid = (req: Request): string =>
  (req as Request & { reqId?: string }).reqId ?? 'no-rid';

const tokenRequestSchema = z.object({
  sub: z.string().min(1),
  role: z.enum(['civilian', 'responder', 'admin']).default('responder'),
});

export function createAuthRouter(): Router {
  const router = Router();

  /**
   * POST /auth/token — Issue a JWT (for testing / admin use).
   * In production, this should be behind proper authentication.
   */
  router.post('/token', (req: Request, res: Response) => {
    const reqId = rid(req);
    const parsed = tokenRequestSchema.safeParse(req.body);
    if (!parsed.success) {
      const fieldErrors = parsed.error.flatten().fieldErrors;
      logger.warn('Auth token request validation failed', { reqId, fieldErrors });
      res.status(400).json({
        error: 'Invalid token request',
        details: fieldErrors,
      });
      return;
    }

    const { sub, role } = parsed.data;
    const token = signToken(sub, role);
    // Log token issuance — sub and role only, never the secret
    logger.info('JWT issued', { reqId, sub, role, expiresIn: '1h' });
    res.status(200).json({ token, expiresIn: '1h' });
  });

  return router;
}
