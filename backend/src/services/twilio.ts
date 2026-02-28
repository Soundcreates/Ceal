/**
 * CEAL Backend — Twilio SMS service.
 *
 * Sends SMS alerts to the escalation number when an SOS is not acknowledged,
 * and distress messages to the victim's registered emergency contacts.
 */

import Twilio from 'twilio';
import { env } from '../config.js';
import { logger } from '../logger.js';

// Prefer API Key auth when available, fall back to Account SID + Auth Token.
const client = (env.TWILIO_API_KEY_SID && env.TWILIO_API_KEY_SECRET)
  ? Twilio(env.TWILIO_API_KEY_SID, env.TWILIO_API_KEY_SECRET, {
      accountSid: env.TWILIO_ACCOUNT_SID,
    })
  : Twilio(env.TWILIO_ACCOUNT_SID, env.TWILIO_AUTH_TOKEN);

export interface SmsPayload {
  sosId: string;
  latitude: number;
  longitude: number;
  timestamp: string;
  message?: string;
  /** Victim's name if the BLE UID resolved to a registered user. */
  victimName?: string | null;
  /** Number of emergency contacts already notified. */
  contactsNotified?: number;
  /** Whether this is a follow-up reminder (30s timer). */
  isReminder?: boolean;
}

export interface ContactSmsPayload {
  /** Phone number of the emergency contact to notify. */
  to: string;
  /** Victim's registered name (shown in the message body). */
  victimName: string | null;
  sosId: string;
  latitude: number;
  longitude: number;
  timestamp: string;
  message?: string;
}

/**
 * Send an escalation SMS with SOS details + Google Maps link.
 */
export async function sendEscalationSms(payload: SmsPayload): Promise<boolean> {
  const mapsUrl = `https://maps.google.com/?q=${payload.latitude},${payload.longitude}`;
  const prefix = payload.isReminder ? '[REMINDER] SOS unacknowledged 30s' : '[SOS ALERT]';
  const victim = payload.victimName ?? 'Unknown';
  const contacts = payload.contactsNotified != null ? ` | Contacts: ${payload.contactsNotified}` : '';
  // Keep body under 160 chars (single GSM-7 segment, no emoji) for Twilio trial compatibility.
  const body = [
    `${prefix} ${victim}${contacts}`,
    `ID: ${payload.sosId}`,
    `${payload.latitude.toFixed(5)},${payload.longitude.toFixed(5)}`,
    mapsUrl,
  ]
    .join('\n');

  try {
    const msg = await client.messages.create({
      body,
      from: env.TWILIO_FROM_NUMBER,
      to: env.TWILIO_ESCALATION_NUMBER,
    });
    logger.info(`Escalation SMS sent to ${env.TWILIO_ESCALATION_NUMBER} — SID: ${msg.sid}`);
    return true;
  } catch (err) {
    logger.error('Failed to send escalation SMS', err);
    return false;
  }
}

/**
 * Send a personal distress SMS to one of the victim's emergency contacts.
 *
 * Sent in parallel with (not instead of) the operator escalation SMS.
 */
export async function sendContactSms(payload: ContactSmsPayload): Promise<boolean> {
  const mapsUrl = `https://maps.google.com/?q=${payload.latitude},${payload.longitude}`;
  const name = payload.victimName ?? 'Someone you know';
  // Keep body under 160 chars (single GSM-7 segment, no emoji) for Twilio trial compatibility.
  const body = [
    `EMERGENCY: ${name} needs help! SOS activated.`,
    `${payload.latitude.toFixed(5)},${payload.longitude.toFixed(5)}`,
    mapsUrl,
    'Call 112 immediately.',
  ]
    .join('\n');

  try {
    const msg = await client.messages.create({
      body,
      from: env.TWILIO_FROM_NUMBER,
      to: payload.to,
    });
    logger.info(`Contact SMS sent to ${payload.to} for SOS ${payload.sosId} — SID: ${msg.sid}`);
    return true;
  } catch (err) {
    logger.error(`Failed to send contact SMS to ${payload.to}`, err);
    return false;
  }
}
