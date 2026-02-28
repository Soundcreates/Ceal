/**
 * CEAL Backend — BLE UID resolution & generation service.
 *
 * - resolveUid: Accepts a 6-byte BLE UID (Buffer) and resolves it to a registered user.
 * - generateBleUid: Deterministic 6-byte BLE UID from userId + server secret.
 */

import type { Pool } from 'pg';
import type { User } from '../models/sos-event.js';
import crypto from 'node:crypto';
import { env } from '../config.js';
import { logger } from '../logger.js';

/**
 * Generate a deterministic 6-byte BLE UID from userId + server secret.
 * Uses SHA-256, then takes the first 6 bytes.
 */
export function generateBleUid(userId: string): Buffer {
  const hash = crypto.createHash('sha256').update(userId + env.SERVER_SECRET).digest();
  return hash.subarray(0, 6);
}

/**
 * Resolve a BLE UID to a registered user.
 *
 * @param pool - PG connection pool
 * @param bleUid - 6-byte BLE UID as a Buffer
 * @returns User record or null if not found
 */
export async function resolveUid(pool: Pool, bleUid: Buffer): Promise<User | null> {
  logger.debug(`UID resolution attempt: ${bleUid.toString('hex')}`);

  const { rows } = await pool.query(
    'SELECT * FROM users WHERE ble_uid = $1',
    [bleUid],
  );

  if (rows.length === 0) {
    logger.debug(`UID resolution miss: ${bleUid.toString('hex')}`);
    return null;
  }

  const row = rows[0];
  logger.info(`UID resolved: ${bleUid.toString('hex')} → user ${row.id}`);

  return rowToUser(row);
}

/**
 * Convert a hex-encoded UID string to a Buffer.
 * Expects exactly 12 hex characters (6 bytes).
 */
export function hexToUidBuffer(hex: string): Buffer {
  return Buffer.from(hex, 'hex');
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function rowToUser(row: any): User {
  return {
    id: row.id,
    name: row.name,
    phone: row.phone,
    bleUid: row.ble_uid,
    language: row.language,
    createdAt: row.created_at instanceof Date ? row.created_at.toISOString() : row.created_at,
  };
}
