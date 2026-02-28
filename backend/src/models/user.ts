/**
 * AfterMath Backend — User model & Zod validation.
 *
 * Represents a civilian user who has onboarded via signup + Aadhaar KYC.
 *
 * DB schema alignment:
 *   users            → name, phone, ble_uid, language, role, kyc_status, aadhaar_*
 *   emergency_contacts → name, phone, priority (per user)
 *   medical_profiles   → blood_group, allergies, conditions (per user)
 */

import { z } from 'zod';

// ---------------------------------------------------------------------------
// KYC status enum
// ---------------------------------------------------------------------------

export const KYC_STATUSES = ['pending', 'verified', 'rejected', 'expired'] as const;
export type KycStatus = (typeof KYC_STATUSES)[number];

export const USER_ROLES = ['civilian', 'responder', 'admin'] as const;
export type UserRole = (typeof USER_ROLES)[number];

// ---------------------------------------------------------------------------
// Zod schemas — emergency contacts & medical profile (nested in signup)
// ---------------------------------------------------------------------------

export const emergencyContactSchema = z.object({
  name: z.string().max(200).optional(),
  phone: z.string().min(5, 'Contact phone too short').max(20),
  priority: z.number().int().min(1).max(10).default(1),
});

export const medicalProfileSchema = z.object({
  bloodGroup: z.string().max(10).optional(),
  allergies: z.string().max(1000).optional(),
  conditions: z.string().max(1000).optional(),
});

// ---------------------------------------------------------------------------
// Zod schemas — signup
// ---------------------------------------------------------------------------

/**
 * Validates POST /onboarding/signup body.
 *
 * Rules:
 *  - name: optional, 2–200 chars, trimmed
 *  - phone: E.164 format (+<country><number>, 10-15 digits)
 *  - language: optional locale code (defaults to 'en')
 *  - emergencyContacts: optional array of up to 10 contacts
 *  - medicalProfile: optional blood group / allergies / conditions
 *
 * The BLE UID is generated server-side (deterministic from userId + secret).
 */
export const signupSchema = z.object({
  name: z
    .string()
    .trim()
    .min(2, 'Name must be at least 2 characters')
    .max(200, 'Name must not exceed 200 characters')
    .optional(),
  phone: z
    .string()
    .regex(/^\+[1-9]\d{9,14}$/, 'Phone must be in E.164 format (e.g. +919876543210)'),
  language: z
    .string()
    .max(10)
    .default('en'),
  emergencyContacts: z
    .array(emergencyContactSchema)
    .max(10, 'Maximum 10 emergency contacts')
    .optional(),
  medicalProfile: medicalProfileSchema.optional(),
});

export type SignupPayload = z.infer<typeof signupSchema>;

// ---------------------------------------------------------------------------
// Zod schemas — Aadhaar ZK verification
// ---------------------------------------------------------------------------

/**
 * Validates POST /onboarding/verify-aadhaar body.
 *
 * The mobile app scans the Aadhaar QR code, generates a ZK proof
 * using @anon-aadhaar/core's `prove()`, then serializes it via
 * `serialize()`. The serialized PCD string is sent to this endpoint.
 *
 * All proof metadata (nullifier, timestamp, demographics) is
 * extracted server-side from the deserialized proof — the client
 * only needs to send the opaque serialized blob and their userId.
 *
 * Fields:
 *  - userId: UUID of the user performing KYC
 *  - serializedProof: the `pcd` string from @anon-aadhaar/core's
 *    serialize() output — a JSON-BigInt stringified proof object
 */
export const aadhaarVerifySchema = z.object({
  userId: z
    .string()
    .uuid('Invalid user ID'),
  serializedProof: z
    .string()
    .min(1, 'Serialized proof is required'),
});

export type AadhaarVerifyPayload = z.infer<typeof aadhaarVerifySchema>;

// ---------------------------------------------------------------------------
// TypeScript interfaces — DB row representations
// ---------------------------------------------------------------------------

export interface User {
  id: string;
  name: string | null;
  phone: string;
  bleUid: string; // hex-encoded 6-byte BLE UID
  language: string | null;
  role: UserRole;
  kycStatus: KycStatus;
  aadhaarNullifier: string | null;
  aadhaarVerifiedAt: string | null;
  aadhaarAgeAbove18: boolean | null;
  aadhaarGender: string | null;
  aadhaarState: string | null;
  createdAt: string;
  updatedAt: string;
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
