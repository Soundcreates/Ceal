/**
 * CEAL Backend — PostgreSQL connection pool.
 */

import pg from 'pg';
import { env } from '../config.js';
import { logger } from '../logger.js';

const { Pool } = pg;

const dbUrl = new URL(env.DATABASE_URL);
const sslMode = dbUrl.searchParams.get('sslmode')?.toLowerCase();
const useSsl =
  sslMode === 'require' ||
  sslMode === 'verify-ca' ||
  sslMode === 'verify-full';

export const pool = new Pool({
  connectionString: env.DATABASE_URL,
  ssl: useSsl ? { rejectUnauthorized: false } : false,
  max: 20,
  idleTimeoutMillis: 30_000,
  connectionTimeoutMillis: 30_000,  // allow Neon cold-start (can take ~10-20s)
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
