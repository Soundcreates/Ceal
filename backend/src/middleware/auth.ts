/**
 * CEAL Backend — JWT authentication middleware.
 *
 * Verifies Bearer tokens on protected routes.
 * Unprotected routes (like SOS ingest from mobile) can skip this middleware.
 */

import type { Request, Response, NextFunction } from 'express';
import crypto from 'node:crypto';
import jwt from 'jsonwebtoken';
import { env } from '../config.js';
import { logger } from '../logger.js';
import type { UserRole } from '../models/user.js';

export interface JwtPayload {
  sub: string;
  role: UserRole;
  iat?: number;
  exp?: number;
}

declare global {
  // eslint-disable-next-line @typescript-eslint/no-namespace
  namespace Express {
    interface Request {
      user?: JwtPayload;
    }
  }
}

/**
 * Middleware that requires a valid JWT Bearer token.
 */
export function requireAuth(req: Request, res: Response, next: NextFunction): void {
  const header = req.headers.authorization;
  if (!header?.startsWith('Bearer ')) {
    res.status(401).json({ error: 'Missing or invalid Authorization header' });
    return;
  }

  const token = header.slice(7);
  try {
    const decoded = jwt.verify(token, env.JWT_SECRET) as JwtPayload;
    req.user = decoded;
    next();
  } catch (err) {
    logger.warn(`JWT verification failed: ${(err as Error).message}`);
    res.status(401).json({ error: 'Invalid or expired token' });
  }
}

/**
 * Optional auth — attaches user if token is present but doesn't reject unauthenticated requests.
 */
export function optionalAuth(req: Request, _res: Response, next: NextFunction): void {
  const header = req.headers.authorization;
  if (header?.startsWith('Bearer ')) {
    const token = header.slice(7);
    try {
      req.user = jwt.verify(token, env.JWT_SECRET) as JwtPayload;
    } catch {
      // Token invalid — proceed as unauthenticated
    }
  }
  next();
}

export function requireRole(...roles: UserRole[]) {
  return (req: Request, res: Response, next: NextFunction): void => {
    if (!req.user) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    if (!roles.includes(req.user.role)) {
      res.status(403).json({ error: 'Insufficient permissions' });
      return;
    }

    next();
  };
}

export function requireServerSecret(req: Request, res: Response, next: NextFunction): void {
  const header = req.headers['x-server-secret'];
  const provided = typeof header === 'string' ? header : Array.isArray(header) ? header[0] : undefined;

  if (!provided) {
    res.status(401).json({ error: 'Missing X-Server-Secret header' });
    return;
  }

  const expected = Buffer.from(env.SERVER_SECRET, 'utf8');
  const actual = Buffer.from(provided, 'utf8');
  const matches = expected.length === actual.length && crypto.timingSafeEqual(expected, actual);

  if (!matches) {
    res.status(401).json({ error: 'Invalid server secret' });
    return;
  }

  next();
}

/**
 * Generate a JWT for a user (for testing or admin endpoints).
 */
export function signToken(sub: string, role: UserRole): string {
  return jwt.sign({ sub, role }, env.JWT_SECRET, {
    expiresIn: env.JWT_EXPIRES_IN as string,
  } as jwt.SignOptions);
}
