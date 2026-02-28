/**
 * AfterMath Backend — Twilio SMS service.
 *
 * Sends SMS alerts to the escalation number when an SOS is not acknowledged,
 * and distress messages to the victim's registered emergency contacts.
 */

import Twilio from 'twilio';
import { env } from '../config.js';
import { logger } from '../logger.js';

// Prefer API Key auth when available, fall back to Account SID + Auth Token.
const client = env.TWILIO_API_KEY_SID && env.TWILIO_API_KEY_SECRET
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
  const body = [
    `🚨 SOS ALERT`,
    payload.message ?? '',
    mapsUrl,
  ]
    .filter(Boolean)
    .join('\n');

  try {
    const msg = await client.messages.create({
      body,
      from: env.TWILIO_FROM_NUMBER,
      to: env.TWILIO_ESCALATION_NUMBER,
    });
    logger.info(`SMS sent to ${env.TWILIO_ESCALATION_NUMBER} — SID: ${msg.sid}`);
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
  const name = payload.victimName ?? 'Someone';
  const body = [
    `🚨 ${name} sent an SOS!`,
    payload.message ?? '',
    mapsUrl,
  ]
    .filter(Boolean)
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
