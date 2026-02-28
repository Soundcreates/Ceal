/**
 * AfterMath Backend — Auth routes (token generation for testing/admin).
 */

import { Router, type Request, type Response } from 'express';
import { z } from 'zod';
import { signToken } from '../middleware/auth.js';

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
    const parsed = tokenRequestSchema.safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json({
        error: 'Invalid token request',
        details: parsed.error.flatten().fieldErrors,
      });
      return;
    }

    const { sub, role } = parsed.data;
    const token = signToken(sub, role);
    res.status(200).json({ token, expiresIn: '1h' });
  });

  return router;
}
