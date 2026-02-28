/**
 * CEAL Backend — SOS Event model & Zod validation.
 *
 * V2 privacy-first protocol:
 *   {id, bleUid (hex), flags, sequence, timestamp, status, relayHops,
 *    receiverLocation: {lat, lon}, rssi?, message?}
 *
 * The BLE packet no longer contains GPS — the receiver attaches its own
 * location when forwarding to the backend.
 */

import { z } from 'zod';

// ---------------------------------------------------------------------------
// Status enum
// ---------------------------------------------------------------------------

export const SOS_STATUSES = [
  'active',
  'relayed',
  'acknowledged',
  'resolved',
  'cancelled',
] as const;

export type SosStatus = (typeof SOS_STATUSES)[number];

// ---------------------------------------------------------------------------
// Zod schemas — used to validate incoming JSON payloads
// ---------------------------------------------------------------------------

/**
 * Validates the POST /sos/ingest body (V2 protocol).
 */
export const sosIngestSchema = z.object({
  id: z.string().min(1).max(128),
  /** Hex-encoded 6-byte BLE UID (12 hex chars) */
  bleUid: z.string().regex(/^[0-9a-fA-F]{12}$/),
  /** BLE advertisement flags (bit 0 = SOS active, bit 1 = medical) */
  flags: z.number().int().min(0).max(255),
  /** Packet sequence number (0-255, wrapping) */
  sequence: z.number().int().min(0).max(255),
  timestamp: z.string().datetime({ offset: true }).or(z.string().datetime()),
  status: z.enum(SOS_STATUSES).default('active'),
  relayHops: z.number().int().min(0).default(0),
  message: z.string().max(64).optional(),
  /** Receiver location (lat/lon of the relay device, NOT the victim) */
  receiverLocation: z.object({
    lat: z.number().min(-90).max(90),
    lon: z.number().min(-180).max(180),
    accuracy: z.number().optional(),
  }).optional(),
  /** RSSI of BLE signal at receiver (dBm, negative) */
  rssi: z.number().int().optional(),
});

// ---------------------------------------------------------------------------
// SOS Type helper — extract type label from flags byte bits 2-5
// ---------------------------------------------------------------------------

const SOS_TYPES = [
  'General SOS',
  'Fire Emergency',
  'Crime Alert',
  'Kidnap Alert',
  'Medical Emergency',
  'Natural Disaster',
] as const;

/**
 * Extract a human-readable SOS type label from the flags byte.
 * Bits 2-5 encode the type code (0-15). Unknown codes default to 'General SOS'.
 */
export function extractSosType(flags: number): string {
  const code = (flags >> 2) & 0x0F;
  return SOS_TYPES[code] ?? 'General SOS';
}

/**
 * Validates the POST /sos/acknowledge body.
 */
export const sosAckSchema = z.object({
  id: z.string().min(1).max(128),
});

// ---------------------------------------------------------------------------
// TypeScript types
// ---------------------------------------------------------------------------

export interface SosEvent {
  id: string;
  bleUid: string;
  flags: number;
  sequence: number;
  /** ISO 8601 string */
  timestamp: string;
  status: SosStatus;
  relayHops: number;
  message?: string;
  /** Receiver location */
  receiverLat?: number;
  receiverLon?: number;
  rssi?: number;
  /** Resolved user ID (if BLE UID matched a registered user) */
  userId?: string;
  /** Human-readable SOS type label extracted from flags */
  sosType?: string;
}

export type SosIngestPayload = z.infer<typeof sosIngestSchema>;
export type SosAckPayload = z.infer<typeof sosAckSchema>;

// ---------------------------------------------------------------------------
// User-related types
// ---------------------------------------------------------------------------

export interface User {
  id: string;
  name: string | null;
  phone: string;
  bleUid: Buffer;
  language: string | null;
  createdAt: string;
}

export interface EmergencyContact {
  id: string;
  userId: string;
  name: string | null;
  phone: string | null;
  priority: number;
}

export interface MedicalProfile {
  userId: string;
  bloodGroup: string | null;
  allergies: string | null;
  conditions: string | null;
}

export interface FullUserProfile {
  user: User;
  contacts: EmergencyContact[];
  medical: MedicalProfile | null;
}
