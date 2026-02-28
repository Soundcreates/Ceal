/**
 * AfterMath Backend — Escalation timer service.
 *
 * When a new SOS is ingested, a timer is started. If the SOS is still
 * active/relayed after the timeout, an SMS is sent to the escalation number.
 */

import { SosRepository } from '../db/sos-repository.js';
import { sendEscalationSms } from './twilio.js';
import { logger } from '../logger.js';

/** Default escalation timeout: 30 seconds (matches kSmsFallbackTimeout in mobile). */
const ESCALATION_TIMEOUT_MS = 30_000;

/** In-memory map of active escalation timers. */
const timers = new Map<string, ReturnType<typeof setTimeout>>();

/** User profile data for enriched escalation. */
export interface EscalationProfile {
  name: string | null;
  phone: string;
  contacts: { name: string | null; phone: string | null; priority: number }[];
  medical: {
    bloodGroup: string | null;
    allergies: string | null;
    conditions: string | null;
  } | null;
}

/**
 * Start an escalation timer for a given SOS event.
 * If the event is not acknowledged within the timeout, send an SMS.
 * Optionally accepts an enriched user profile for enhanced escalation.
 *
 * V2: latitude/longitude come from the receiver, not the victim — may be null
 * if no receiver location was attached.
 */
export function startEscalationTimer(
  sosId: string,
  latitude: number | undefined,
  longitude: number | undefined,
  timestamp: string,
  message: string | undefined,
  repo: SosRepository,
  profile?: EscalationProfile,
): void {
  // Clear any existing timer for this SOS ID (idempotent)
  cancelEscalationTimer(sosId);

  const timer = setTimeout(async () => {
    timers.delete(sosId);
    try {
      // Re-check if still active/relayed before sending
      const event = await repo.findById(sosId);
      if (!event || event.status === 'acknowledged' || event.status === 'resolved' || event.status === 'cancelled') {
        logger.info(`Escalation skipped for ${sosId} — status: ${event?.status ?? 'not found'}`);
        return;
      }

      logger.warn(`SOS ${sosId} unacknowledged after ${ESCALATION_TIMEOUT_MS / 1000}s — sending SMS`);

      // Build enriched payload for SMS
      const enrichedMessage = profile
        ? [
            message,
            `Name: ${profile.name ?? 'Unknown'}`,
            `Phone: ${profile.phone}`,
            profile.medical?.bloodGroup ? `Blood: ${profile.medical.bloodGroup}` : '',
            profile.medical?.allergies ? `Allergies: ${profile.medical.allergies}` : '',
            profile.medical?.conditions ? `Conditions: ${profile.medical.conditions}` : '',
            profile.contacts.length > 0
              ? `Emergency contacts: ${profile.contacts.map((c) => `${c.name ?? 'N/A'} (${c.phone ?? 'N/A'})`).join(', ')}`
              : '',
          ]
            .filter(Boolean)
            .join(' | ')
        : message;

      await sendEscalationSms({
        sosId,
        latitude: latitude ?? 0,
        longitude: longitude ?? 0,
        timestamp,
        message: enrichedMessage,
      });
    } catch (err) {
      logger.error(`Escalation timer error for ${sosId}`, err);
    }
  }, ESCALATION_TIMEOUT_MS);

  // Prevent the timer from keeping the process alive on shutdown
  timer.unref();
  timers.set(sosId, timer);
  logger.debug(`Escalation timer started for ${sosId} (${ESCALATION_TIMEOUT_MS / 1000}s)`);
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
