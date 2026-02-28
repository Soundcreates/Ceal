/**
 * AfterMath Backend — Twilio SMS service.
 *
 * Sends SMS alerts to the escalation number when an SOS is not acknowledged,
 * and distress messages to the victim's registered emergency contacts.
 */

import Twilio from 'twilio';
import { env } from '../config.js';
import { logger } from '../logger.js';

// Use API Key auth (preferred for production over Account SID + Auth Token).
const client = Twilio(env.TWILIO_API_KEY_SID, env.TWILIO_API_KEY_SECRET, {
  accountSid: env.TWILIO_ACCOUNT_SID,
});

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
    `🚨 AfterMath SOS ALERT`,
    `ID: ${payload.sosId}`,
    `Time: ${payload.timestamp}`,
    `Location: ${payload.latitude.toFixed(6)}, ${payload.longitude.toFixed(6)}`,
    `Map: ${mapsUrl}`,
    payload.message ? `Msg: ${payload.message}` : '',
    '',
    'This SOS was NOT acknowledged within the timeout window.',
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
  const name = payload.victimName ?? 'Someone you know';
  const body = [
    `🚨 EMERGENCY: ${name} needs help!`,
    `They activated the AfterMath SOS distress signal.`,
    `Approx location: ${payload.latitude.toFixed(6)}, ${payload.longitude.toFixed(6)}`,
    `Map: ${mapsUrl}`,
    `Time: ${payload.timestamp}`,
    payload.message ? `Message: "${payload.message}"` : '',
    '',
    'Please respond immediately or contact emergency services.',
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
