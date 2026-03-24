/**
 * CEAL Backend — Escalation timer service.
 *
 * Persists pending escalations in PostgreSQL so a process restart does not
 * silently drop active SOS follow-up timers.
 */

import type { Pool } from 'pg';
import { SosRepository } from '../db/sos-repository.js';
import { UserRepository } from '../db/user-repository.js';
import { logger } from '../logger.js';
import { sendEscalationSms } from './twilio.js';

const ESCALATION_TIMEOUT_MS = 30_000;
const timers = new Map<string, ReturnType<typeof setTimeout>>();

export async function startEscalationTimer(pool: Pool, sosId: string): Promise<void> {
  const inserted = await pool.query<{ fire_at: Date | string }>(
    `INSERT INTO pending_escalations (sos_id, fire_at)
     VALUES ($1, NOW() + ($2::text)::interval)
     ON CONFLICT (sos_id) DO NOTHING
     RETURNING fire_at`,
    [sosId, `${ESCALATION_TIMEOUT_MS / 1000} seconds`],
  );

  if (inserted.rows[0]) {
    armEscalationTimer(pool, sosId, inserted.rows[0].fire_at);
    return;
  }

  if (!timers.has(sosId)) {
    const existing = await pool.query<{ fire_at: Date | string }>(
      'SELECT fire_at FROM pending_escalations WHERE sos_id = $1 AND fired = FALSE',
      [sosId],
    );
    if (existing.rows[0]) {
      armEscalationTimer(pool, sosId, existing.rows[0].fire_at);
    }
  }
}

export async function cancelEscalationTimer(pool: Pool, sosId: string): Promise<void> {
  const existing = timers.get(sosId);
  if (existing) {
    clearTimeout(existing);
    timers.delete(sosId);
  }

  await pool.query('DELETE FROM pending_escalations WHERE sos_id = $1', [sosId]);
  logger.debug(`Escalation timer cancelled for ${sosId}`);
}

export async function recoverPendingEscalations(pool: Pool): Promise<void> {
  const { rows } = await pool.query<{ sos_id: string; fire_at: Date | string }>(
    'SELECT sos_id, fire_at FROM pending_escalations WHERE fired = FALSE',
  );

  for (const row of rows) {
    armEscalationTimer(pool, row.sos_id, row.fire_at);
  }

  logger.info(`Recovered ${rows.length} pending escalations`);
}

export function cancelAllTimers(): void {
  for (const [id, timer] of timers) {
    clearTimeout(timer);
    timers.delete(id);
  }
  logger.info('All escalation timers cancelled');
}

function armEscalationTimer(pool: Pool, sosId: string, fireAtValue: Date | string): void {
  const fireAt = fireAtValue instanceof Date ? fireAtValue : new Date(fireAtValue);
  const delayMs = Math.max(0, fireAt.getTime() - Date.now());

  const existing = timers.get(sosId);
  if (existing) {
    clearTimeout(existing);
  }

  const timer = setTimeout(() => {
    void fireEscalation(pool, sosId);
  }, delayMs);
  timer.unref();

  timers.set(sosId, timer);
}

async function fireEscalation(pool: Pool, sosId: string): Promise<void> {
  timers.delete(sosId);

  const claimed = await pool.query(
    `UPDATE pending_escalations
     SET fired = TRUE
     WHERE sos_id = $1 AND fired = FALSE
     RETURNING sos_id`,
    [sosId],
  );
  if (claimed.rows.length === 0) {
    return;
  }

  try {
    const repo = new SosRepository(pool);
    const userRepo = new UserRepository(pool);
    const event = await repo.findById(sosId);
    if (!event || ['acknowledged', 'resolved', 'cancelled'].includes(event.status)) {
      logger.info(`Escalation skipped for ${sosId} (status: ${event?.status ?? 'not found'})`);
      return;
    }

    if (event.receiverLat == null || event.receiverLon == null) {
      logger.warn(`Escalation fired for ${sosId} without receiver coordinates`);
      return;
    }

    const user = event.userId ? await userRepo.findById(event.userId) : null;
    await sendEscalationSms({
      sosId: event.id,
      latitude: event.receiverLat,
      longitude: event.receiverLon,
      timestamp: event.timestamp,
      message: event.message,
      victimName: user?.name ?? null,
      isReminder: true,
    });

    logger.warn(`SOS ${sosId} escalated after ${ESCALATION_TIMEOUT_MS / 1000}s`);
  } catch (err) {
    logger.error(`Escalation timer error for ${sosId}`, err);
  }
}
