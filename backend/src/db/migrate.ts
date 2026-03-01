/**
 * CEAL Backend — Database migration.
 *
 * Run with: npm run migrate
 * Idempotent — safe to run multiple times.
 */

import pg from 'pg';
import 'dotenv/config';
import { env } from '../config.js';

const { Pool } = pg;

const CREATE_SOS_EVENTS = `
DROP TABLE IF EXISTS sos_events CASCADE;
CREATE TABLE sos_events (
  id           TEXT PRIMARY KEY,
  ble_uid      TEXT NOT NULL,
  flags        INTEGER NOT NULL DEFAULT 0,
  sequence     INTEGER NOT NULL DEFAULT 0,
  receiver_lat DOUBLE PRECISION,
  receiver_lon DOUBLE PRECISION,
  rssi         INTEGER,
  user_id      UUID REFERENCES users(id) ON DELETE SET NULL,
  timestamp    TIMESTAMPTZ NOT NULL,
  status       TEXT NOT NULL DEFAULT 'active'
               CHECK (status IN ('active', 'relayed', 'acknowledged', 'resolved', 'cancelled')),
  relay_hops   INTEGER NOT NULL DEFAULT 0,
  message      TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
`;

const CREATE_UPDATED_AT_TRIGGER = `
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
CREATE INDEX IF NOT EXISTS idx_sos_events_ble_uid  ON sos_events (ble_uid);
CREATE INDEX IF NOT EXISTS idx_sos_events_status   ON sos_events (status);
CREATE INDEX IF NOT EXISTS idx_sos_events_created  ON sos_events (created_at);
`;

// ---------------------------------------------------------------------------
// User identity tables
// ---------------------------------------------------------------------------

const CREATE_USERS = `
CREATE TABLE IF NOT EXISTS users (
  id                    UUID PRIMARY KEY,
  name                  TEXT,
  phone                 TEXT UNIQUE NOT NULL,
  ble_uid               BYTEA UNIQUE NOT NULL,
  language              TEXT,
  role                  TEXT NOT NULL DEFAULT 'civilian'
                        CHECK (role IN ('civilian', 'responder', 'admin')),
  kyc_status            TEXT NOT NULL DEFAULT 'pending'
                        CHECK (kyc_status IN ('pending', 'verified', 'rejected', 'expired')),
  aadhaar_nullifier     TEXT UNIQUE,
  aadhaar_verified_at   TIMESTAMPTZ,
  aadhaar_age_above_18  BOOLEAN,
  aadhaar_gender        TEXT,
  aadhaar_state         TEXT,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
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

const CREATE_USER_INDEXES = `
CREATE INDEX IF NOT EXISTS idx_users_phone              ON users (phone);
CREATE INDEX IF NOT EXISTS idx_users_ble_uid            ON users (ble_uid);
CREATE INDEX IF NOT EXISTS idx_users_aadhaar_nullifier  ON users (aadhaar_nullifier);
CREATE INDEX IF NOT EXISTS idx_users_kyc_status         ON users (kyc_status);
`;

const CREATE_USER_UPDATED_AT_TRIGGER = `
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'set_updated_at_users'
  ) THEN
    CREATE TRIGGER set_updated_at_users
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();
  END IF;
END;
$$;
`;

const CREATE_AADHAAR_QR_SCANS = `
CREATE TABLE IF NOT EXISTS aadhaar_qr_scans (
  id            UUID PRIMARY KEY,
  user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  source        TEXT NOT NULL DEFAULT 'photo',
  image_sha256  TEXT NOT NULL,
  image_data    BYTEA NOT NULL,
  decoded_xml   TEXT NOT NULL,
  processed_by  TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
`;

const CREATE_AADHAAR_QR_SCANS_INDEXES = `
CREATE INDEX IF NOT EXISTS idx_aadhaar_qr_scans_user    ON aadhaar_qr_scans (user_id);
CREATE INDEX IF NOT EXISTS idx_aadhaar_qr_scans_created ON aadhaar_qr_scans (created_at);
CREATE INDEX IF NOT EXISTS idx_aadhaar_qr_scans_sha     ON aadhaar_qr_scans (image_sha256);
`;

const CREATE_MANUAL_KYC_SUBMISSIONS = `
CREATE TABLE IF NOT EXISTS manual_kyc_submissions (
  id            UUID PRIMARY KEY,
  user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name          TEXT NOT NULL,
  age           INTEGER NOT NULL CHECK (age >= 1 AND age <= 120),
  sex           TEXT NOT NULL CHECK (sex IN ('M', 'F', 'T')),
  dob           TEXT,
  yob           TEXT,
  state         TEXT NOT NULL,
  district      TEXT NOT NULL,
  pincode       TEXT NOT NULL,
  source        TEXT NOT NULL DEFAULT 'manual_form',
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
`;

const CREATE_MANUAL_KYC_SUBMISSIONS_INDEXES = `
CREATE INDEX IF NOT EXISTS idx_manual_kyc_submissions_user
  ON manual_kyc_submissions (user_id);
CREATE INDEX IF NOT EXISTS idx_manual_kyc_submissions_created
  ON manual_kyc_submissions (created_at);
`;

// ---------------------------------------------------------------------------
// Disaster reports table
// ---------------------------------------------------------------------------

const CREATE_DISASTER_REPORTS = `
CREATE TABLE IF NOT EXISTS disaster_reports (
  id                    UUID PRIMARY KEY,
  user_id               UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  lat                   DOUBLE PRECISION NOT NULL,
  lon                   DOUBLE PRECISION NOT NULL,
  image_url             TEXT NOT NULL,
  image_hash            TEXT NOT NULL,
  category              TEXT NOT NULL
                        CHECK (category IN ('fire', 'flood', 'accident', 'infrastructure', 'medical', 'other')),
  severity_score        SMALLINT NOT NULL CHECK (severity_score >= 1 AND severity_score <= 5),
  llm_confidence        REAL NOT NULL CHECK (llm_confidence >= 0 AND llm_confidence <= 1),
  llm_raw_response      JSONB,
  verification_status   TEXT NOT NULL DEFAULT 'pending'
                        CHECK (verification_status IN ('pending', 'verified', 'rejected', 'flagged')),
  rejection_reason      TEXT,
  authority_status      TEXT NOT NULL DEFAULT 'pending'
                        CHECK (authority_status IN ('pending', 'dispatched', 'resolved', 'ignored')),
  description           TEXT,
  linked_sos_id         TEXT REFERENCES sos_events(id) ON DELETE SET NULL,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
`;

const CREATE_DISASTER_REPORTS_INDEXES = `
CREATE INDEX IF NOT EXISTS idx_disaster_reports_user       ON disaster_reports (user_id, created_at);
CREATE INDEX IF NOT EXISTS idx_disaster_reports_geo        ON disaster_reports (lat, lon);
CREATE INDEX IF NOT EXISTS idx_disaster_reports_created    ON disaster_reports (created_at);
CREATE INDEX IF NOT EXISTS idx_disaster_reports_category   ON disaster_reports (category, verification_status);
CREATE INDEX IF NOT EXISTS idx_disaster_reports_hash       ON disaster_reports (image_hash);
CREATE INDEX IF NOT EXISTS idx_disaster_reports_status     ON disaster_reports (verification_status, authority_status);
`;

const CREATE_DISASTER_REPORTS_UPDATED_AT_TRIGGER = `
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'set_updated_at_disaster_reports'
  ) THEN
    CREATE TRIGGER set_updated_at_disaster_reports
    BEFORE UPDATE ON disaster_reports
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();
  END IF;
END;
$$;
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

    await pool.query(`
      CREATE OR REPLACE FUNCTION update_updated_at_column()
      RETURNS TRIGGER AS $$
      BEGIN
        NEW.updated_at = NOW();
        RETURN NEW;
      END;
      $$ language 'plpgsql';
    `);
    console.log('  ✅ update_updated_at function');

    // User identity tables must be created before sos_events (FK dependency)
    await pool.query(CREATE_USERS);
    console.log('  ✅ users table');
    await pool.query(CREATE_EMERGENCY_CONTACTS);
    console.log('  ✅ emergency_contacts table');
    await pool.query(CREATE_MEDICAL_PROFILES);
    console.log('  ✅ medical_profiles table');
    await pool.query(CREATE_USER_INDEXES);
    console.log('  ✅ user indexes');
    await pool.query(CREATE_USER_UPDATED_AT_TRIGGER);
    console.log('  ✅ users updated_at trigger');
    await pool.query(CREATE_AADHAAR_QR_SCANS);
    console.log('  ✅ aadhaar_qr_scans table');
    await pool.query(CREATE_AADHAAR_QR_SCANS_INDEXES);
    console.log('  ✅ aadhaar_qr_scans indexes');
    await pool.query(CREATE_MANUAL_KYC_SUBMISSIONS);
    console.log('  ✅ manual_kyc_submissions table');
    await pool.query(CREATE_MANUAL_KYC_SUBMISSIONS_INDEXES);
    console.log('  ✅ manual_kyc_submissions indexes');

    // Disaster reports
    await pool.query(CREATE_DISASTER_REPORTS);
    console.log('  ✅ disaster_reports table');
    await pool.query(CREATE_DISASTER_REPORTS_INDEXES);
    console.log('  ✅ disaster_reports indexes');
    await pool.query(CREATE_DISASTER_REPORTS_UPDATED_AT_TRIGGER);
    console.log('  ✅ disaster_reports updated_at trigger');

    // SOS events table (references users.id)
    await pool.query(CREATE_SOS_EVENTS);
    console.log('  ✅ sos_events table (V2)');
    await pool.query(CREATE_UPDATED_AT_TRIGGER);
    console.log('  ✅ updated_at trigger');
    await pool.query(CREATE_INDEXES);
    console.log('  ✅ indexes');

    console.log('Migrations complete.');
  } catch (err) {
    console.error('Migration failed:', err);
    process.exit(1);
  } finally {
    await pool.end();
  }
}

migrate();
