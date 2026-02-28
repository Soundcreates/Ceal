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
  message: { error: 'Too many requests, please try again later.' },
});
