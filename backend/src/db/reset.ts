/**
 * CEAL Backend — Database reset utility.
 *
 * Clears all application data while keeping schema, indexes, and triggers.
 *
 * Usage:
 *   npm run db:reset -- --yes
 */

import 'dotenv/config';
import pg from 'pg';

const { Pool } = pg;

const TABLES_TO_TRUNCATE = [
  'aadhaar_qr_scans',
  'manual_kyc_submissions',
  'emergency_contacts',
  'medical_profiles',
  'disaster_reports',
  'sos_events',
  'users',
] as const;

function readDatabaseUrl(): string {
  const url = process.env.DATABASE_URL;
  if (!url) {
    throw new Error('DATABASE_URL is required');
  }
  return url;
}

function shouldUseSsl(databaseUrl: string): boolean {
  const parsed = new URL(databaseUrl);
  const sslMode = parsed.searchParams.get('sslmode')?.toLowerCase();
  return sslMode === 'require' || sslMode === 'verify-ca' || sslMode === 'verify-full';
}

function ensureConfirmationFlag(): void {
  const confirmed = process.argv.includes('--yes');
  if (!confirmed) {
    throw new Error('Refusing to reset DB without explicit confirmation. Run: npm run db:reset -- --yes');
  }
}

async function resetDatabase(): Promise<void> {
  ensureConfirmationFlag();

  const databaseUrl = readDatabaseUrl();
  const pool = new Pool({
    connectionString: databaseUrl,
    ssl: shouldUseSsl(databaseUrl) ? { rejectUnauthorized: false } : false,
  });

  try {
    const quotedTables = TABLES_TO_TRUNCATE.map((name) => `"public"."${name}"`).join(', ');

    await pool.query('BEGIN');
    await pool.query(`TRUNCATE TABLE ${quotedTables} RESTART IDENTITY CASCADE`);
    await pool.query('COMMIT');

    console.log(`✅ Database cleared. Truncated ${TABLES_TO_TRUNCATE.length} tables.`);
  } catch (error) {
    await pool.query('ROLLBACK');
    throw error;
  } finally {
    await pool.end();
  }
}

resetDatabase().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : String(error);
  console.error(`❌ DB reset failed: ${message}`);
  process.exit(1);
});
