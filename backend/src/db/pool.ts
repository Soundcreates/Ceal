/**
 * AfterMath Backend — PostgreSQL connection pool.
 */

import pg from 'pg';
import { env } from '../config.js';
import { logger } from '../logger.js';

const { Pool } = pg;

export const pool = new Pool({
  connectionString: env.DATABASE_URL,
  ssl: false,
  max: 20,
  idleTimeoutMillis: 30_000,
  connectionTimeoutMillis: 10_000,
});

pool.on('error', (err) => {
  logger.error('Unexpected PG pool error', err);
});

/**
 * Gracefully shut down the pool (called on SIGTERM).
 */
export async function closePool(): Promise<void> {
  await pool.end();
  logger.info('PG pool closed');
}
