/**
 * CEAL Backend — User profile service.
 *
 * Fetches a complete user profile (user + emergency contacts + medical info)
 * for use in escalation enrichment.
 */

import type { Pool } from 'pg';
import type {
  User,
  EmergencyContact,
  MedicalProfile,
  FullUserProfile,
} from '../models/sos-event.js';
import { rowToUser } from './uid-resolver.js';
import { logger } from '../logger.js';

/**
 * Fetch user record by ID.
 */
export async function getUserById(pool: Pool, userId: string): Promise<User | null> {
  const { rows } = await pool.query('SELECT * FROM users WHERE id = $1', [userId]);
  return rows.length > 0 ? rowToUser(rows[0]) : null;
}

/**
 * Fetch emergency contacts for a user, ordered by priority.
 */
export async function getEmergencyContacts(pool: Pool, userId: string): Promise<EmergencyContact[]> {
  const { rows } = await pool.query(
    'SELECT * FROM emergency_contacts WHERE user_id = $1 ORDER BY priority ASC',
    [userId],
  );
  return rows.map(rowToContact);
}

/**
 * Fetch medical profile for a user.
 */
export async function getMedicalProfile(pool: Pool, userId: string): Promise<MedicalProfile | null> {
  const { rows } = await pool.query(
    'SELECT * FROM medical_profiles WHERE user_id = $1',
    [userId],
  );
  return rows.length > 0 ? rowToMedical(rows[0]) : null;
}

/**
 * Fetch the full user profile (user + contacts + medical).
 */
export async function getFullUserProfile(pool: Pool, userId: string): Promise<FullUserProfile | null> {
  const user = await getUserById(pool, userId);
  if (!user) {
    logger.debug(`User profile not found: ${userId}`);
    return null;
  }

  const [contacts, medical] = await Promise.all([
    getEmergencyContacts(pool, userId),
    getMedicalProfile(pool, userId),
  ]);

  logger.debug(`Full profile loaded for user ${userId}: ${contacts.length} contacts`);

  return { user, contacts, medical };
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function rowToContact(row: any): EmergencyContact {
  return {
    id: row.id,
    userId: row.user_id,
    name: row.name,
    phone: row.phone,
    priority: row.priority,
  };
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function rowToMedical(row: any): MedicalProfile {
  return {
    userId: row.user_id,
    bloodGroup: row.blood_group,
    allergies: row.allergies,
    conditions: row.conditions,
  };
}
