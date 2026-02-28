/**
 * AfterMath Backend — Database migration.
 *
 * Run with: npm run migrate
 * Idempotent — safe to run multiple times.
 */

import pg from 'pg';
import 'dotenv/config';
import { env } from '../config.js';

const { Pool } = pg;

const CREATE_SOS_EVENTS = `
CREATE TABLE IF NOT EXISTS sos_events (
  id              TEXT PRIMARY KEY,
  device_id_hash  INTEGER[] NOT NULL,           -- 2-element array [byte0, byte1]
  latitude        DOUBLE PRECISION NOT NULL,
  longitude       DOUBLE PRECISION NOT NULL,
  timestamp       TIMESTAMPTZ NOT NULL,
  status          TEXT NOT NULL DEFAULT 'active'
                  CHECK (status IN ('active', 'relayed', 'acknowledged', 'resolved', 'cancelled')),
  relay_hops      INTEGER NOT NULL DEFAULT 0,
  message         TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
`;

const CREATE_UPDATED_AT_TRIGGER = `
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ language 'plpgsql';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'set_updated_at_sos_events'
  ) THEN
    CREATE TRIGGER set_updated_at_sos_events
    BEFORE UPDATE ON sos_events
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();
  END IF;
END;
$$;
`;

const CREATE_INDEXES = `
CREATE INDEX IF NOT EXISTS idx_sos_events_status   ON sos_events (status);
CREATE INDEX IF NOT EXISTS idx_sos_events_created  ON sos_events (created_at);
`;

// ---------------------------------------------------------------------------
// User identity tables
// ---------------------------------------------------------------------------

const CREATE_USERS = `
CREATE TABLE IF NOT EXISTS users (
  id          UUID PRIMARY KEY,
  name        TEXT,
  phone       TEXT UNIQUE NOT NULL,
  ble_uid     BYTEA UNIQUE NOT NULL,
  language    TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
`;

const CREATE_EMERGENCY_CONTACTS = `
CREATE TABLE IF NOT EXISTS emergency_contacts (
  id        UUID PRIMARY KEY,
  user_id   UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name      TEXT,
  phone     TEXT,
  priority  INTEGER NOT NULL DEFAULT 1
);
CREATE INDEX IF NOT EXISTS idx_emergency_contacts_user ON emergency_contacts (user_id);
`;

const CREATE_MEDICAL_PROFILES = `
CREATE TABLE IF NOT EXISTS medical_profiles (
  user_id     UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  blood_group TEXT,
  allergies   TEXT,
  conditions  TEXT
);
`;

async function migrate(): Promise<void> {
  const dbUrl = new URL(env.DATABASE_URL);
  const sslMode = dbUrl.searchParams.get('sslmode')?.toLowerCase();
  const useSsl =
    sslMode === 'require' ||
    sslMode === 'verify-ca' ||
    sslMode === 'verify-full';

  const pool = new Pool({
    connectionString: env.DATABASE_URL,
    ssl: useSsl ? { rejectUnauthorized: false } : false,
  });

  try {
    console.log('Running migrations...');
    await pool.query(CREATE_SOS_EVENTS);
    console.log('  ✅ sos_events table');
    await pool.query(CREATE_UPDATED_AT_TRIGGER);
    console.log('  ✅ updated_at trigger');
    await pool.query(CREATE_INDEXES);
    console.log('  ✅ indexes');

    // User identity tables
    await pool.query(CREATE_USERS);
    console.log('  ✅ users table');
    await pool.query(CREATE_EMERGENCY_CONTACTS);
    console.log('  ✅ emergency_contacts table');
    await pool.query(CREATE_MEDICAL_PROFILES);
    console.log('  ✅ medical_profiles table');

    console.log('Migrations complete.');
  } catch (err) {
    console.error('Migration failed:', err);
    process.exit(1);
  } finally {
    await pool.end();
  }
}

migrate();
