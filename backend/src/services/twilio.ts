/**
 * AfterMath Backend — Twilio SMS service.
 *
 * Sends SMS alerts to the escalation number when an SOS is not acknowledged.
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
