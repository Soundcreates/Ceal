/**
 * CEAL Backend — User data-access layer.
 *
 * All queries are parameterised. No string interpolation in SQL.
 *
 * Tables:
 *  - users              → name, phone, ble_uid, language, role, kyc_status, aadhaar_*
 *  - emergency_contacts → name, phone, priority (per user)
 *  - medical_profiles   → blood_group, allergies, conditions (per user)
 */

import type { Pool as PgPool } from 'pg';
import type {
  User,
  SignupPayload,
  EmergencyContact,
  MedicalProfile,
  ManualKycPayload,
} from '../models/user.js';
import { randomUUID } from 'node:crypto';
import { generateBleUid } from '../services/uid-resolver.js';

export class UserRepository {
  constructor(private readonly pool: PgPool) {}

  // ─────────────────────────────────────────────────────────────────────────
  // User CRUD
  // ─────────────────────────────────────────────────────────────────────────

  /**
   * Create a new user from signup data. Returns the created user.
   * If the caller provides `data.bleUid` (device-generated, 12 hex chars),
   * that UID is used verbatim so the device's BLE broadcast matches the DB.
   * Otherwise the server generates a deterministic UID from userId + secret.
   * Throws on duplicate phone or BLE UID (unique constraint violation).
   */
  async create(data: SignupPayload): Promise<User> {
    const id = randomUUID();
    const bleUid = data.bleUid
      ? Buffer.from(data.bleUid, 'hex')
      : generateBleUid(id);
    const { rows } = await this.pool.query(
      `INSERT INTO users (id, name, phone, ble_uid, language)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING *`,
      [id, data.name ?? null, data.phone, bleUid, data.language ?? 'en'],
    );
    return this.rowToUser(rows[0]);
  }

  /**
   * Find user by primary key.
   */
  async findById(id: string): Promise<User | null> {
    const { rows } = await this.pool.query(
      'SELECT * FROM users WHERE id = $1',
      [id],
    );
    return rows.length > 0 ? this.rowToUser(rows[0]) : null;
  }

  /**
   * Find user by phone number (E.164 exact match).
   */
  async findByPhone(phone: string): Promise<User | null> {
    const { rows } = await this.pool.query(
      'SELECT * FROM users WHERE phone = $1',
      [phone],
    );
    return rows.length > 0 ? this.rowToUser(rows[0]) : null;
  }

  /**
   * Check if an Aadhaar nullifier hash has already been used by any user.
   * Returns the user ID that owns it, or null.
   */
  async findByNullifier(nullifierHash: string): Promise<User | null> {
    const { rows } = await this.pool.query(
      'SELECT * FROM users WHERE aadhaar_nullifier = $1',
      [nullifierHash],
    );
    return rows.length > 0 ? this.rowToUser(rows[0]) : null;
  }

  /**
   * Look up the full user profile (user + contacts + medical) by BLE UID hex string.
   * Returns null if no registered user owns this UID.
   */
  async findFullProfileByBleUid(
    bleUidHex: string,
  ): Promise<{ user: User; contacts: EmergencyContact[]; medical: MedicalProfile | null } | null> {
    // ble_uid is stored as BYTEA — decode hex to binary for the query
    const { rows: userRows } = await this.pool.query(
      `SELECT * FROM users WHERE ble_uid = decode($1, 'hex')`,
      [bleUidHex],
    );
    if (userRows.length === 0) return null;
    const user = this.rowToUser(userRows[0]);

    const { rows: contactRows } = await this.pool.query(
      `SELECT * FROM emergency_contacts WHERE user_id = $1 ORDER BY priority`,
      [user.id],
    );
    const contacts: EmergencyContact[] = contactRows.map((r) => ({
      id: r.id,
      userId: r.user_id,
      name: r.name ?? null,
      phone: r.phone ?? null,
      priority: r.priority,
    }));

    const { rows: medRows } = await this.pool.query(
      `SELECT * FROM medical_profiles WHERE user_id = $1`,
      [user.id],
    );
    const medical: MedicalProfile | null = medRows.length > 0
      ? { userId: medRows[0].user_id, bloodGroup: medRows[0].blood_group ?? null, allergies: medRows[0].allergies ?? null, conditions: medRows[0].conditions ?? null }
      : null;

    return { user, contacts, medical };
  }

  /**
   * Update KYC status and store Aadhaar verification metadata.
   * Called after successful ZK proof verification.
   */
  async updateKycVerified(
    userId: string,
    nullifierHash: string,
    aadhaarAgeAbove18: boolean,
    aadhaarGender: string | null,
    aadhaarState: string | null,
  ): Promise<User | null> {
    const { rows } = await this.pool.query(
      `UPDATE users
       SET kyc_status = 'verified',
           aadhaar_nullifier = $2,
           aadhaar_verified_at = NOW(),
           aadhaar_age_above_18 = $3,
           aadhaar_gender = $4,
           aadhaar_state = $5
       WHERE id = $1 AND kyc_status = 'pending'
       RETURNING *`,
      [userId, nullifierHash, aadhaarAgeAbove18, aadhaarGender, aadhaarState],
    );
    return rows.length > 0 ? this.rowToUser(rows[0]) : null;
  }

  /**
   * Reject KYC for a user (e.g. invalid proof, fraud detection).
   */
  async updateKycRejected(userId: string): Promise<User | null> {
    const { rows } = await this.pool.query(
      `UPDATE users
       SET kyc_status = 'rejected'
       WHERE id = $1 AND kyc_status = 'pending'
       RETURNING *`,
      [userId],
    );
    return rows.length > 0 ? this.rowToUser(rows[0]) : null;
  }

  /**
   * Mark KYC as verified based on Aadhaar QR XML extraction.
   * This route does not use ZK nullifier-based deduplication.
   */
  async updateKycVerifiedFromQr(
    userId: string,
    aadhaarAgeAbove18: boolean,
    aadhaarGender: string | null,
    aadhaarState: string | null,
  ): Promise<User | null> {
    const { rows } = await this.pool.query(
      `UPDATE users
       SET kyc_status = 'verified',
           aadhaar_verified_at = NOW(),
           aadhaar_age_above_18 = $2,
           aadhaar_gender = $3,
           aadhaar_state = $4
       WHERE id = $1 AND kyc_status IN ('pending', 'expired')
       RETURNING *`,
      [userId, aadhaarAgeAbove18, aadhaarGender, aadhaarState],
    );
    return rows.length > 0 ? this.rowToUser(rows[0]) : null;
  }

  /**
   * Update user's role (e.g. civilian → responder).
   */
  async updateRole(userId: string, role: string): Promise<User | null> {
    const { rows } = await this.pool.query(
      `UPDATE users SET role = $2 WHERE id = $1 RETURNING *`,
      [userId, role],
    );
    return rows.length > 0 ? this.rowToUser(rows[0]) : null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Emergency contacts
  // ─────────────────────────────────────────────────────────────────────────

  /**
   * Create one or more emergency contacts for a user.
   * Returns the list of created contacts.
   */
  async createEmergencyContacts(
    userId: string,
    contacts: Array<{ name?: string; phone: string; priority: number }>,
  ): Promise<EmergencyContact[]> {
    const created: EmergencyContact[] = [];
    for (const contact of contacts) {
      const contactId = randomUUID();
      await this.pool.query(
        `INSERT INTO emergency_contacts (id, user_id, name, phone, priority)
         VALUES ($1, $2, $3, $4, $5)`,
        [contactId, userId, contact.name ?? null, contact.phone, contact.priority],
      );
      created.push({
        id: contactId,
        userId,
        name: contact.name ?? null,
        phone: contact.phone,
        priority: contact.priority,
      });
    }
    return created;
  }

  /**
   * Create or update medical profile for a user (upsert).
   */
  async upsertMedicalProfile(
    userId: string,
    profile: { bloodGroup?: string; allergies?: string; conditions?: string },
  ): Promise<MedicalProfile> {
    await this.pool.query(
      `INSERT INTO medical_profiles (user_id, blood_group, allergies, conditions)
       VALUES ($1, $2, $3, $4)
       ON CONFLICT (user_id) DO UPDATE SET
         blood_group = EXCLUDED.blood_group,
         allergies   = EXCLUDED.allergies,
         conditions  = EXCLUDED.conditions`,
      [userId, profile.bloodGroup ?? null, profile.allergies ?? null, profile.conditions ?? null],
    );
    return {
      userId,
      bloodGroup: profile.bloodGroup ?? null,
      allergies: profile.allergies ?? null,
      conditions: profile.conditions ?? null,
    };
  }

  /**
   * Persist manual KYC details when Aadhaar scanning is skipped.
   */
  async saveManualKycSubmission(data: ManualKycPayload): Promise<void> {
    await this.pool.query(
      `INSERT INTO manual_kyc_submissions
         (id, user_id, name, age, sex, dob, yob, state, district, pincode, source)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, 'manual_form')`,
      [
        randomUUID(),
        data.userId,
        data.name,
        data.age,
        data.sex,
        data.dob ?? null,
        data.yob ?? null,
        data.state,
        data.district,
        data.pincode,
      ],
    );
  }

  /**
   * Apply a minimal subset of manual KYC details to users table.
   * KYC status remains pending for manual-review flow.
   */
  async updateUserFromManualKyc(
    userId: string,
    name: string,
    ageAbove18: boolean,
    sex: string,
    state: string,
  ): Promise<User | null> {
    const { rows } = await this.pool.query(
      `UPDATE users
       SET name = COALESCE(NULLIF($2, ''), name),
           aadhaar_age_above_18 = $3,
           aadhaar_gender = $4,
           aadhaar_state = $5
       WHERE id = $1
       RETURNING *`,
      [userId, name, ageAbove18, sex, state],
    );
    return rows.length > 0 ? this.rowToUser(rows[0]) : null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Row mapper
  // ─────────────────────────────────────────────────────────────────────────

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  private rowToUser(row: any): User {
    return {
      id: row.id,
      name: row.name ?? null,
      phone: row.phone,
      bleUid: row.ble_uid instanceof Buffer
        ? row.ble_uid.toString('hex')
        : (typeof row.ble_uid === 'string' ? row.ble_uid : ''),
      language: row.language ?? null,
      role: row.role ?? 'civilian',
      kycStatus: row.kyc_status ?? 'pending',
      aadhaarNullifier: row.aadhaar_nullifier ?? null,
      aadhaarVerifiedAt: row.aadhaar_verified_at
        ? (row.aadhaar_verified_at instanceof Date
            ? row.aadhaar_verified_at.toISOString()
            : row.aadhaar_verified_at)
        : null,
      aadhaarAgeAbove18: row.aadhaar_age_above_18 ?? null,
      aadhaarGender: row.aadhaar_gender ?? null,
      aadhaarState: row.aadhaar_state ?? null,
      createdAt: row.created_at instanceof Date ? row.created_at.toISOString() : row.created_at,
      updatedAt: row.updated_at
        ? (row.updated_at instanceof Date ? row.updated_at.toISOString() : row.updated_at)
        : (row.created_at instanceof Date ? row.created_at.toISOString() : row.created_at),
    };
  }
}
