/**
 * AfterMath Backend — SOS Events data-access layer.
 */

import type { Pool as PgPool } from 'pg';
import type { SosEvent, SosStatus } from '../models/sos-event.js';

export class SosRepository {
  constructor(private readonly pool: PgPool) {}

  /**
   * Insert or update (upsert) an SOS event.
   * On conflict, update relay_hops if higher and keep the latest status.
   */
  async upsert(event: SosEvent): Promise<SosEvent> {
    const { rows } = await this.pool.query<SosEvent>(
      `INSERT INTO sos_events (id, device_id_hash, latitude, longitude, timestamp, status, relay_hops, message)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
       ON CONFLICT (id) DO UPDATE SET
         relay_hops = GREATEST(sos_events.relay_hops, EXCLUDED.relay_hops),
         status     = EXCLUDED.status,
         updated_at = NOW()
       RETURNING *`,
      [
        event.id,
        event.deviceIdHash,
        event.latitude,
        event.longitude,
        event.timestamp,
        event.status,
        event.relayHops,
        event.message ?? null,
      ],
    );
    return this.rowToEvent(rows[0]!);
  }

  /**
   * Fetch a single SOS event by ID.
   */
  async findById(id: string): Promise<SosEvent | null> {
    const { rows } = await this.pool.query(
      'SELECT * FROM sos_events WHERE id = $1',
      [id],
    );
    return rows.length > 0 ? this.rowToEvent(rows[0]) : null;
  }

  /**
   * Acknowledge an SOS event — update status to 'acknowledged'.
   */
  async acknowledge(id: string): Promise<SosEvent | null> {
    const { rows } = await this.pool.query(
      `UPDATE sos_events SET status = 'acknowledged'
       WHERE id = $1 AND status IN ('active', 'relayed')
       RETURNING *`,
      [id],
    );
    return rows.length > 0 ? this.rowToEvent(rows[0]) : null;
  }

  /**
   * Fetch all active or relayed SOS events (for the responder dashboard).
   */
  async findActive(): Promise<SosEvent[]> {
    const { rows } = await this.pool.query(
      `SELECT * FROM sos_events
       WHERE status IN ('active', 'relayed')
       ORDER BY timestamp DESC
       LIMIT 200`,
    );
    return rows.map((r) => this.rowToEvent(r));
  }

  /**
   * Update the status of an SOS event.
   */
  async updateStatus(id: string, status: SosStatus): Promise<SosEvent | null> {
    const { rows } = await this.pool.query(
      `UPDATE sos_events SET status = $2 WHERE id = $1 RETURNING *`,
      [id, status],
    );
    return rows.length > 0 ? this.rowToEvent(rows[0]) : null;
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  private rowToEvent(row: any): SosEvent {
    return {
      id: row.id,
      deviceIdHash: row.device_id_hash,
      latitude: parseFloat(row.latitude),
      longitude: parseFloat(row.longitude),
      timestamp: row.timestamp instanceof Date ? row.timestamp.toISOString() : row.timestamp,
      status: row.status,
      relayHops: row.relay_hops,
      message: row.message ?? undefined,
    };
  }
}
