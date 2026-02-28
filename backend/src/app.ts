/**
 * AfterMath Backend — Express application factory.
 *
 * Separated from the server listener so tests can import the app
 * without starting a listening server.
 */

import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import type { Pool } from 'pg';

import { env } from './config.js';
import { apiLimiter } from './middleware/rate-limit.js';
import { createSosRouter } from './routes/sos.js';
import { createHealthRouter } from './routes/health.js';
import { createAuthRouter } from './routes/auth.js';
import { createUsersRouter } from './routes/users.js';
import { createOnboardingRouter } from './routes/onboarding.js';

export function createApp(pool: Pool): express.Express {
  const app = express();

  // ---------------------------------------------------------------------------
  // Global middleware
  // ---------------------------------------------------------------------------
  app.use(helmet());
  app.use(
    cors({
      origin: env.CORS_ORIGIN.split(',').map((o) => o.trim()),
      methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
      allowedHeaders: ['Content-Type', 'Authorization'],
    }),
  );
  app.use(express.json({ limit: '12mb' }));
  app.use(apiLimiter);

  // ---------------------------------------------------------------------------
  // Routes — all under /v1 prefix to match mobile's kApiBaseUrl
  // ---------------------------------------------------------------------------
  app.use('/v1/health', createHealthRouter(pool));
  app.use('/v1/auth', createAuthRouter());
  app.use('/v1/onboarding', createOnboardingRouter(pool));
  app.use('/v1/sos', createSosRouter(pool));
  app.use('/v1/users', createUsersRouter(pool));

  // Root health check (convenience)
  app.get('/', (_req, res) => {
    res.json({ service: 'aftermath-backend', version: '1.0.0' });
  });

  // ---------------------------------------------------------------------------
  // 404 catch-all
  // ---------------------------------------------------------------------------
  app.use((_req, res) => {
    res.status(404).json({ error: 'Not found' });
  });

  return app;
}
