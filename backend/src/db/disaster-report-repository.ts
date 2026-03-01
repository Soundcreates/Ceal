/**
 * AfterMath Backend — Disaster Reports data-access layer.
 */

import type { Pool as PgPool } from 'pg';
import type {
  DisasterReport,
  DisasterCategory,
  VerificationStatus,
  AuthorityStatus,
  DisasterStats,
  HeatmapPoint,
} from '../models/disaster-report.js';

export interface CreateDisasterReport {
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
  description: string | null;
  linkedSosId: string | null;
}

export class DisasterReportRepository {
  constructor(private readonly pool: PgPool) {}

  /**
   * Insert a new disaster report.
   */
  async create(report: CreateDisasterReport): Promise<DisasterReport> {
    const { rows } = await this.pool.query(
      `INSERT INTO disaster_reports
         (id, user_id, lat, lon, image_url, image_hash, category,
          severity_score, llm_confidence, llm_raw_response,
          verification_status, rejection_reason, description, linked_sos_id)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)
       RETURNING *`,
      [
        report.id,
        report.userId,
        report.lat,
        report.lon,
        report.imageUrl,
        report.imageHash,
        report.category,
        report.severityScore,
        report.llmConfidence,
        report.llmRawResponse ? JSON.stringify(report.llmRawResponse) : null,
        report.verificationStatus,
        report.rejectionReason,
        report.description,
        report.linkedSosId,
      ],
    );
    return this.rowToReport(rows[0]!);
  }

  /**
   * Find a single report by ID.
   */
  async findById(id: string): Promise<DisasterReport | null> {
    const { rows } = await this.pool.query(
      'SELECT * FROM disaster_reports WHERE id = $1',
      [id],
    );
    return rows.length > 0 ? this.rowToReport(rows[0]) : null;
  }

  /**
   * Paginated feed with filters.
   */
  async findFeed(opts: {
    category?: DisasterCategory;
    severityMin?: number;
    since?: string;
    neLat?: number;
    neLon?: number;
    swLat?: number;
    swLon?: number;
    page: number;
    limit: number;
  }): Promise<{ reports: DisasterReport[]; total: number }> {
    const conditions: string[] = ["verification_status = 'verified'"];
    const params: unknown[] = [];
    let i = 1;

    if (opts.category) {
      conditions.push(`category = $${i++}`);
      params.push(opts.category);
    }
    if (opts.severityMin) {
      conditions.push(`severity_score >= $${i++}`);
      params.push(opts.severityMin);
    }
    if (opts.since) {
      conditions.push(`created_at >= $${i++}`);
      params.push(opts.since);
    }
    if (
      opts.neLat != null &&
      opts.neLon != null &&
      opts.swLat != null &&
      opts.swLon != null
    ) {
      conditions.push(`lat BETWEEN $${i++} AND $${i++}`);
      params.push(opts.swLat, opts.neLat);
      conditions.push(`lon BETWEEN $${i++} AND $${i++}`);
      params.push(opts.swLon, opts.neLon);
    }

    const where = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';
    const offset = (opts.page - 1) * opts.limit;

    const countResult = await this.pool.query(
      `SELECT COUNT(*)::int AS total FROM disaster_reports ${where}`,
      params,
    );
    const total = countResult.rows[0]?.total ?? 0;

    const dataResult = await this.pool.query(
      `SELECT * FROM disaster_reports ${where}
       ORDER BY created_at DESC
       LIMIT $${i++} OFFSET $${i++}`,
      [...params, opts.limit, offset],
    );

    return {
      reports: dataResult.rows.map((r) => this.rowToReport(r)),
      total,
    };
  }

  /**
   * Update authority status of a report.
   */
  async updateAuthorityStatus(
    id: string,
    status: AuthorityStatus,
  ): Promise<DisasterReport | null> {
    const { rows } = await this.pool.query(
      `UPDATE disaster_reports SET authority_status = $2
       WHERE id = $1 RETURNING *`,
      [id, status],
    );
    return rows.length > 0 ? this.rowToReport(rows[0]) : null;
  }

  /**
   * Check how many reports a user has submitted in the last hour.
   */
  async countRecentByUser(userId: string): Promise<number> {
    const { rows } = await this.pool.query(
      `SELECT COUNT(*)::int AS cnt FROM disaster_reports
       WHERE user_id = $1 AND created_at > NOW() - INTERVAL '1 hour'`,
      [userId],
    );
    return rows[0]?.cnt ?? 0;
  }

  /**
   * Check if an image hash was submitted in the last 24 hours.
   */
  async findRecentByHash(hash: string): Promise<boolean> {
    const { rows } = await this.pool.query(
      `SELECT 1 FROM disaster_reports
       WHERE image_hash = $1 AND created_at > NOW() - INTERVAL '24 hours'
       LIMIT 1`,
      [hash],
    );
    return rows.length > 0;
  }

  /**
   * Aggregate statistics for a time range.
   */
  async stats(range: '24h' | '7d' | '30d'): Promise<DisasterStats> {
    const interval = range === '24h' ? '24 hours' : range === '7d' ? '7 days' : '30 days';

    const { rows } = await this.pool.query(
      `SELECT
         COUNT(*)::int AS total,
         COUNT(*) FILTER (WHERE verification_status = 'verified')::int AS verified,
         COUNT(*) FILTER (WHERE verification_status = 'rejected')::int AS rejected,
         COUNT(*) FILTER (WHERE verification_status = 'flagged')::int AS flagged,
         COUNT(*) FILTER (WHERE verification_status = 'pending')::int AS pending
       FROM disaster_reports
       WHERE created_at > NOW() - $1::interval`,
      [interval],
    );

    const catResult = await this.pool.query(
      `SELECT category, COUNT(*)::int AS cnt
       FROM disaster_reports
       WHERE created_at > NOW() - $1::interval AND verification_status = 'verified'
       GROUP BY category`,
      [interval],
    );

    const sevResult = await this.pool.query(
      `SELECT severity_score, COUNT(*)::int AS cnt
       FROM disaster_reports
       WHERE created_at > NOW() - $1::interval AND verification_status = 'verified'
       GROUP BY severity_score`,
      [interval],
    );

    const sosResult = await this.pool.query(
      `SELECT COUNT(*)::int AS cnt FROM sos_events
       WHERE created_at > NOW() - $1::interval`,
      [interval],
    );

    const byCategory: Record<string, number> = {};
    for (const row of catResult.rows) byCategory[row.category] = row.cnt;

    const bySeverity: Record<number, number> = {};
    for (const row of sevResult.rows) bySeverity[row.severity_score] = row.cnt;

    const base = rows[0] ?? { total: 0, verified: 0, rejected: 0, flagged: 0, pending: 0 };
    return {
      totalReports: base.total,
      verified: base.verified,
      rejected: base.rejected,
      flagged: base.flagged,
      pending: base.pending,
      byCategory,
      bySeverity,
      sosCount: sosResult.rows[0]?.cnt ?? 0,
    };
  }

  /**
   * Geo-clustered points for heatmap rendering.
   * Groups by rounded lat/lon at the given decimal precision.
   */
  async heatmap(opts: {
    precision: number;
    since?: string;
    category?: DisasterCategory;
  }): Promise<HeatmapPoint[]> {
    const conditions: string[] = ["verification_status = 'verified'"];
    const params: unknown[] = [];
    let i = 1;

    if (opts.since) {
      conditions.push(`created_at >= $${i++}`);
      params.push(opts.since);
    }
    if (opts.category) {
      conditions.push(`category = $${i++}`);
      params.push(opts.category);
    }

    const where = conditions.join(' AND ');
    const p = opts.precision;

    const { rows } = await this.pool.query(
      `SELECT
         ROUND(lat::numeric, ${p}) AS lat,
         ROUND(lon::numeric, ${p}) AS lon,
         COUNT(*)::int AS count,
         ROUND(AVG(severity_score)::numeric, 1) AS avg_severity
       FROM disaster_reports
       WHERE ${where}
       GROUP BY ROUND(lat::numeric, ${p}), ROUND(lon::numeric, ${p})
       ORDER BY count DESC
       LIMIT 2000`,
      params,
    );

    return rows.map((r) => ({
      lat: parseFloat(r.lat),
      lon: parseFloat(r.lon),
      count: r.count,
      avgSeverity: parseFloat(r.avg_severity),
    }));
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  private rowToReport(row: any): DisasterReport {
    return {
      id: row.id,
      userId: row.user_id,
      lat: parseFloat(row.lat),
      lon: parseFloat(row.lon),
      imageUrl: row.image_url,
      imageHash: row.image_hash,
      category: row.category,
      severityScore: row.severity_score,
      llmConfidence: parseFloat(row.llm_confidence),
      llmRawResponse: row.llm_raw_response ?? null,
      verificationStatus: row.verification_status,
      rejectionReason: row.rejection_reason ?? null,
      authorityStatus: row.authority_status,
      description: row.description ?? null,
      linkedSosId: row.linked_sos_id ?? null,
      createdAt:
        row.created_at instanceof Date
          ? row.created_at.toISOString()
          : row.created_at,
      updatedAt:
        row.updated_at instanceof Date
          ? row.updated_at.toISOString()
          : row.updated_at,
    };
  }
}
