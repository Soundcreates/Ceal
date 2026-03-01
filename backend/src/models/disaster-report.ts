/**
 * AfterMath Backend — Disaster Report model & Zod validation.
 *
 * Users submit GPS-pinned photo evidence of disasters. An LLM verifies
 * the image before the report is stored.
 */

import { z } from 'zod';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

export const DISASTER_CATEGORIES = [
  'fire',
  'flood',
  'accident',
  'infrastructure',
  'medical',
  'other',
] as const;

export type DisasterCategory = (typeof DISASTER_CATEGORIES)[number];

export const VERIFICATION_STATUSES = [
  'pending',
  'verified',
  'rejected',
  'flagged',
] as const;

export type VerificationStatus = (typeof VERIFICATION_STATUSES)[number];

export const AUTHORITY_STATUSES = [
  'pending',
  'dispatched',
  'resolved',
  'ignored',
] as const;

export type AuthorityStatus = (typeof AUTHORITY_STATUSES)[number];

// ---------------------------------------------------------------------------
// Zod schemas
// ---------------------------------------------------------------------------

/**
 * Validates the non-file fields of POST /disaster/report.
 * The image is handled separately via multer.
 */
export const disasterReportBodySchema = z.object({
  lat: z.coerce.number().min(-90).max(90),
  lon: z.coerce.number().min(-180).max(180),
  description: z.string().max(500).optional(),
});

/**
 * Validates query params for GET /disaster/feed.
 */
export const disasterFeedQuerySchema = z.object({
  category: z.enum(DISASTER_CATEGORIES).optional(),
  severity_min: z.coerce.number().int().min(1).max(5).optional(),
  since: z.string().datetime({ offset: true }).or(z.string().datetime()).optional(),
  ne_lat: z.coerce.number().min(-90).max(90).optional(),
  ne_lon: z.coerce.number().min(-180).max(180).optional(),
  sw_lat: z.coerce.number().min(-90).max(90).optional(),
  sw_lon: z.coerce.number().min(-180).max(180).optional(),
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(20),
});

/**
 * Validates PATCH /disaster/:id/status body.
 */
export const authorityStatusUpdateSchema = z.object({
  authority_status: z.enum(AUTHORITY_STATUSES),
});

/**
 * Validates GET /disaster/heatmap query.
 */
export const heatmapQuerySchema = z.object({
  precision: z.coerce.number().int().min(0).max(4).default(2),
  since: z.string().datetime({ offset: true }).or(z.string().datetime()).optional(),
  category: z.enum(DISASTER_CATEGORIES).optional(),
});

/**
 * Validates GET /disaster/stats query.
 */
export const statsQuerySchema = z.object({
  range: z.enum(['24h', '7d', '30d']).default('24h'),
});

// ---------------------------------------------------------------------------
// TypeScript interfaces
// ---------------------------------------------------------------------------

export interface DisasterReport {
  id: string;
  userId: string;
  lat: number;
  lon: number;
  imageUrl: string;
  imageHash: string;
  category: DisasterCategory;
  severityScore: number;
  llmConfidence: number;
  llmRawResponse: Record<string, unknown> | null;
  verificationStatus: VerificationStatus;
  rejectionReason: string | null;
  authorityStatus: AuthorityStatus;
  description: string | null;
  linkedSosId: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface GeminiVerificationResult {
  isReal: boolean;
  category: DisasterCategory;
  severity: number;
  confidence: number;
  reasoning: string;
  flags: string[];
}

export interface DisasterStats {
  totalReports: number;
  verified: number;
  rejected: number;
  flagged: number;
  pending: number;
  byCategory: Record<string, number>;
  bySeverity: Record<number, number>;
  sosCount: number;
}

export interface HeatmapPoint {
  lat: number;
  lon: number;
  count: number;
  avgSeverity: number;
}
