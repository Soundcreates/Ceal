/**
 * CEAL Backend — Server entry point.
 *
 * Starts Express, connects to PostgreSQL, and listens for requests.
 */

import { env } from './config.js';
import { logger } from './logger.js';
import { pool, closePool } from './db/pool.js';
import { createApp } from './app.js';
import { cancelAllTimers } from './services/escalation.js';

const app = createApp(pool);

const server = app.listen(env.PORT, () => {
  logger.info(`CEAL backend listening on port ${env.PORT} [${env.NODE_ENV}]`);

  // Warm up the Neon connection pool immediately so the first real request
  // (signup, SOS ingest, etc.) does not incur a 10 s cold-start delay.
  pool.query('SELECT 1').then(() => {
    logger.info('DB pool warmed up');
  }).catch((err) => {
    logger.warn('DB warmup failed (will retry on first request)', { message: (err as Error).message });
  });
});

// ---------------------------------------------------------------------------
// Graceful shutdown
// ---------------------------------------------------------------------------

async function shutdown(signal: string): Promise<void> {
  logger.info(`Received ${signal} — shutting down…`);
  cancelAllTimers();

  server.close(async () => {
    await closePool();
    logger.info('Server closed');
    process.exit(0);
  });

  // Force exit after 10s if graceful shutdown stalls
  setTimeout(() => {
    logger.error('Forced exit after timeout');
    process.exit(1);
  }, 10_000).unref();
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

export default app;
