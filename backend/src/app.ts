/**
 * CEAL Backend — Express application factory.
 *
 * Separated from the server listener so tests can import the app
 * without starting a listening server.
 */

import crypto from 'node:crypto';
import express, { type Request, type Response, type NextFunction } from 'express';
import cors from 'cors';
import helmet from 'helmet';
import type { Pool } from 'pg';

import { env } from './config.js';
import { logger } from './logger.js';
import { apiLimiter } from './middleware/rate-limit.js';
import { createSosRouter } from './routes/sos.js';
import { createHealthRouter } from './routes/health.js';
import { createAuthRouter } from './routes/auth.js';
import { createUsersRouter } from './routes/users.js';
import { createOnboardingRouter } from './routes/onboarding.js';
import { createDisasterRouter } from './routes/disaster.js';
import { createAdminRouter } from './routes/admin.js';

// ---------------------------------------------------------------------------
// Sensitive fields to redact from logged request bodies
// ---------------------------------------------------------------------------
const REDACT_KEYS = new Set(['password', 'token', 'secret', 'authorization', 'rawXml']);

function redactBody(obj: unknown, depth = 0): unknown {
  if (depth > 4 || obj === null || typeof obj !== 'object') return obj;
  if (Array.isArray(obj)) return obj.map((v) => redactBody(v, depth + 1));
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(obj as Record<string, unknown>)) {
    out[k] = REDACT_KEYS.has(k.toLowerCase()) ? '[REDACTED]' : redactBody(v, depth + 1);
  }
  return out;
}

export function createApp(pool: Pool): express.Express {
  const app = express();

  // ---------------------------------------------------------------------------
  // Global middleware
  // ---------------------------------------------------------------------------
  app.use(helmet());
  app.use(
    cors({
      origin: "*",
      methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
      allowedHeaders: ['Content-Type', 'Authorization'],
    }),
  );
  app.use(express.json({ limit: '12mb' }));
  app.use(apiLimiter);

  // ---------------------------------------------------------------------------
  // Request logging middleware
  // Each request gets a short random ID so all its log lines are correlated.
  // ---------------------------------------------------------------------------
  app.use((req: Request, res: Response, next: NextFunction) => {
    const reqId = crypto.randomBytes(4).toString('hex');
    (req as Request & { reqId: string }).reqId = reqId;
    const startMs = Date.now();

    const bodyStr =
      req.body && Object.keys(req.body).length > 0
        ? ` body=${JSON.stringify(redactBody(req.body))}`
        : '';
    const ip = req.ip ?? req.socket.remoteAddress ?? 'unknown';
    const auth = req.headers.authorization
      ? ` auth=${req.headers.authorization.split(' ')[0]}`
      : '';

    logger.info(`→ ${req.method} ${req.originalUrl}${bodyStr} ip=${ip}${auth}`, { reqId });

    res.on('finish', () => {
      const durationMs = Date.now() - startMs;
      const level = res.statusCode >= 500 ? 'error' : res.statusCode >= 400 ? 'warn' : 'info';
      logger[level](
        `← ${req.method} ${req.originalUrl} ${res.statusCode} ip=${ip}`,
        { reqId, durationMs },
      );
    });

    next();
  });

  // ---------------------------------------------------------------------------
  // Routes — all under /v1 prefix to match mobile's kApiBaseUrl
  // ---------------------------------------------------------------------------
  app.use('/v1/health', createHealthRouter(pool));
  app.use('/v1/auth', createAuthRouter());
  app.use('/v1/onboarding', createOnboardingRouter(pool));
  app.use('/v1/sos', createSosRouter(pool));
  app.use('/v1/users', createUsersRouter(pool));
  app.use('/v1/disaster', createDisasterRouter(pool));
  app.use('/v1/admin', createAdminRouter(pool));

  // Root health check (convenience)
  app.get('/', (_req, res) => {
    res.json({ service: 'ceal-backend', version: '1.0.0' });
  });

  // ---------------------------------------------------------------------------
  // 404 catch-all
  // ---------------------------------------------------------------------------
  app.use((req: Request, res: Response) => {
    logger.warn(`404 ${req.method} ${req.originalUrl}`);
    res.status(404).json({ error: 'Not found' });
  });

  // ---------------------------------------------------------------------------
  // Global error handler — catches anything thrown in route handlers
  // ---------------------------------------------------------------------------
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  app.use((err: Error, req: Request, res: Response, _next: NextFunction) => {
    const reqId = (req as Request & { reqId?: string }).reqId;
    logger.error(
      `Unhandled error on ${req.method} ${req.originalUrl}: ${err.message}`,
      { reqId, stack: err.stack },
    );
    res.status(500).json({
      error: 'Internal server error',
      ...(env.NODE_ENV !== 'production' && { detail: err.message }),
    });
  });

  return app;
}
