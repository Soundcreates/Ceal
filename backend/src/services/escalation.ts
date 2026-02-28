/**
 * CEAL Backend — Escalation timer service.
 *
 * Tracks whether an SOS is acknowledged within the timeout window.
 * An SMS is already sent immediately on ingest; this timer only logs if
 * the event remains unacknowledged (no duplicate SMS).
 */

import { SosRepository } from '../db/sos-repository.js';
import { logger } from '../logger.js';

/** Default escalation timeout: 30 seconds (matches kSmsFallbackTimeout in mobile). */
const ESCALATION_TIMEOUT_MS = 30_000;

/** In-memory map of active escalation timers. */
const timers = new Map<string, ReturnType<typeof setTimeout>>();

/**
 * Start an escalation timer for a given SOS event.
 * If the event is not acknowledged within the timeout, send an SMS.
 */
export function startEscalationTimer(
  sosId: string,
  repo: SosRepository,
): void {
  // Clear any existing timer for this SOS ID (idempotent)
  cancelEscalationTimer(sosId);

  const timer = setTimeout(async () => {
    timers.delete(sosId);
    try {
      const event = await repo.findById(sosId);
      if (!event || event.status === 'acknowledged' || event.status === 'resolved' || event.status === 'cancelled') {
        logger.info(`Escalation timer: ${sosId} already handled (status: ${event?.status ?? 'not found'})`);
        return;
      }
      // SMS was already sent immediately on ingest — just log the warning.
      logger.warn(`SOS ${sosId} still unacknowledged after ${ESCALATION_TIMEOUT_MS / 1000}s`);
    } catch (err) {
      logger.error(`Escalation timer error for ${sosId}`, err);
    }
  }, ESCALATION_TIMEOUT_MS);

  // Prevent the timer from keeping the process alive on shutdown
  timer.unref();
  timers.set(sosId, timer);
  logger.info(`SOS escalation timer started`);
}

/**
 * Cancel an escalation timer (e.g. when the SOS is acknowledged).
 */
export function cancelEscalationTimer(sosId: string): void {
  const existing = timers.get(sosId);
  if (existing) {
    clearTimeout(existing);
    timers.delete(sosId);
    logger.debug(`Escalation timer cancelled for ${sosId}`);
  }
}

/**
 * Cancel all active timers (cleanup on shutdown).
 */
export function cancelAllTimers(): void {
  for (const [id, timer] of timers) {
    clearTimeout(timer);
    timers.delete(id);
  }
  logger.info('All escalation timers cancelled');
}
