/**
 * AfterMath Backend — SOS Event model & Zod validation.
 *
 * Matches the JSON contract from the Flutter mobile app:
 *   {id, deviceIdHash: [int,int], latitude, longitude, timestamp, status, relayHops, message?}
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
 * Validates the POST /sos/ingest body.
 */
export const sosIngestSchema = z.object({
  id: z.string().min(1).max(128),
  deviceIdHash: z.array(z.number().int().min(0).max(255)).length(2),
  latitude: z.number().min(-90).max(90),
  longitude: z.number().min(-180).max(180),
  timestamp: z.string().datetime({ offset: true }).or(z.string().datetime()),
  status: z.enum(SOS_STATUSES).default('active'),
  relayHops: z.number().int().min(0).default(0),
  message: z.string().max(64).optional(),
});

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
  deviceIdHash: number[];
  latitude: number;
  longitude: number;
  /** ISO 8601 string */
  timestamp: string;
  status: SosStatus;
  relayHops: number;
  message?: string;
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
