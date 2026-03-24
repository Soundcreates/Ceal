/**
 * CEAL Backend — Rate limiting middleware.
 */

import rateLimit from 'express-rate-limit';
import { env } from '../config.js';

export const apiLimiter = rateLimit({
  windowMs: env.RATE_LIMIT_WINDOW_MS,
  max: env.RATE_LIMIT_MAX,
  standardHeaders: true,
  legacyHeaders: false,
  skip: (req) => req.originalUrl === '/v1/sos/ingest',
  message: { error: 'Too many requests, please try again later.' },
});

export const sosIngestLimiter = rateLimit({
  windowMs: env.RATE_LIMIT_WINDOW_MS,
  max: Math.max(env.RATE_LIMIT_MAX, 1000),
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many SOS ingest requests, please try again shortly.' },
});
