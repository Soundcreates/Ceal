/**
 * CEAL Backend — Winston logger.
 *
 * Outputs human-readable coloured lines to the console.
 * Each line includes: timestamp · level · request-id (if present) · message.
 */

import winston from 'winston';
import { env } from './config.js';

const { combine, timestamp, printf, colorize, errors } = winston.format;

/**
 * Main console format — one line per log entry.
 * Example:
 *   2026-02-28 14:03:01 [info] [req-abc123] POST /v1/sos/ingest → 201 (42ms)
 */
const consoleFormat = printf(({ level, message, timestamp: ts, stack, reqId, durationMs }) => {
  const rid = reqId ? ` [${reqId}]` : '';
  const dur = durationMs !== undefined ? ` (${durationMs}ms)` : '';
  const body = stack ?? message;
  return `${ts} [${level}]${rid}${dur}: ${body}`;
});

export const logger = winston.createLogger({
  level: env.LOG_LEVEL,
  format: combine(
    errors({ stack: true }),
    timestamp({ format: 'YYYY-MM-DD HH:mm:ss.SSS' }),
    consoleFormat,
  ),
  transports: [
    new winston.transports.Console({
      format: combine(colorize({ all: true }), consoleFormat),
    }),
  ],
});

/** Quick child logger that always attaches a request-id field. */
export function reqLogger(reqId: string) {
  return logger.child({ reqId });
}
