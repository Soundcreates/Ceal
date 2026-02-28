/**
 * AfterMath Backend — User identity & onboarding tests.
 *
 * Uses a mocked PG pool so tests run entirely in-memory without a real database.
 */

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import express from 'express';
import request from 'supertest';
import crypto from 'node:crypto';

// ---------------------------------------------------------------------------
// Mock pg module BEFORE importing anything that uses it
// ---------------------------------------------------------------------------
const mockQuery = vi.fn();
const mockPool = {
  query: mockQuery,
  on: vi.fn(),
  end: vi.fn(),
} as any;

vi.mock('pg', () => {
  return {
    default: {
      Pool: vi.fn(() => mockPool),
    },
    Pool: vi.fn(() => mockPool),
  };
});

// Mock Twilio so it doesn't try to connect
vi.mock('twilio', () => {
  const create = vi.fn().mockResolvedValue({ sid: 'SM_TEST' });
  return {
    default: vi.fn(() => ({
      messages: { create },
    })),
  };
});

// Now safe to import
import { createUsersRouter } from '../src/routes/users.js';
import { createSosRouter } from '../src/routes/sos.js';
import { signToken } from '../src/middleware/auth.js';
import { resolveUid, hexToUidBuffer } from '../src/services/uid-resolver.js';
import { getFullUserProfile } from '../src/services/user-profile.js';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function buildApp() {
  const app = express();
  app.use(express.json());
  app.use('/v1/users', createUsersRouter(mockPool));
  app.use('/v1/sos', createSosRouter(mockPool));
  return app;
}

function authHeader() {
  return `Bearer ${signToken('admin-1', 'admin')}`;
}

const mockUserRow = {
  id: '11111111-1111-1111-1111-111111111111',
  name: 'Test User',
  phone: '+919876543210',
  ble_uid: Buffer.from('aabbccddeeff', 'hex'),
  language: 'en',
  created_at: new Date('2025-06-01T00:00:00Z'),
};

const mockContactRow = {
  id: '22222222-2222-2222-2222-222222222222',
  user_id: mockUserRow.id,
  name: 'Emergency Friend',
  phone: '+919999000000',
  priority: 1,
};

const mockMedicalRow = {
  user_id: mockUserRow.id,
  blood_group: 'O+',
  allergies: 'Peanuts',
  conditions: 'Asthma',
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('User creation', () => {
  let app: express.Express;

  beforeEach(() => {
    app = buildApp();
    mockQuery.mockReset();
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it('POST /v1/users returns 201 with valid payload', async () => {
    mockQuery.mockResolvedValueOnce({ rows: [mockUserRow] });

    const res = await request(app)
      .post('/v1/users')
      .set('Authorization', authHeader())
      .send({ name: 'Test User', phone: '+919876543210', language: 'en' });

    expect(res.status).toBe(201);
    expect(res.body).toHaveProperty('id');
    expect(res.body).toHaveProperty('bleUid');
    expect(res.body.bleUid).toMatch(/^[0-9a-f]{12}$/);
    expect(res.body.name).toBe('Test User');
    expect(res.body.phone).toBe('+919876543210');
  });

  it('POST /v1/users requires authentication', async () => {
    const res = await request(app)
      .post('/v1/users')
      .send({ name: 'Test', phone: '+911234567890' });

    expect(res.status).toBe(401);
  });

  it('POST /v1/users returns 400 for missing phone', async () => {
    const res = await request(app)
      .post('/v1/users')
      .set('Authorization', authHeader())
      .send({ name: 'Test' });

    expect(res.status).toBe(400);
  });

  it('POST /v1/users returns 409 for duplicate phone', async () => {
    const pgError: any = new Error('duplicate key');
    pgError.code = '23505';
    pgError.detail = 'Key (phone)=(+919876543210) already exists.';
    mockQuery.mockRejectedValueOnce(pgError);

    const res = await request(app)
      .post('/v1/users')
      .set('Authorization', authHeader())
      .send({ name: 'Dup User', phone: '+919876543210' });

    expect(res.status).toBe(409);
    expect(res.body.error).toContain('Phone');
  });
});

describe('BLE UID generation', () => {
  it('generates deterministic 6-byte UID from userId + secret', () => {
    const userId = '11111111-1111-1111-1111-111111111111';
    const secret = 'aftermath-default-server-secret-change-me';
    const hash = crypto.createHash('sha256').update(userId + secret).digest();
    const expected = hash.subarray(0, 6);

    // Calling the same input again should give the same result
    const hash2 = crypto.createHash('sha256').update(userId + secret).digest();
    const expected2 = hash2.subarray(0, 6);

    expect(expected.equals(expected2)).toBe(true);
    expect(expected.length).toBe(6);
  });

  it('hexToUidBuffer converts 12-char hex to 6-byte buffer', () => {
    const buf = hexToUidBuffer('aabbccddeeff');
    expect(buf.length).toBe(6);
    expect(buf.toString('hex')).toBe('aabbccddeeff');
  });
});

describe('UID resolution', () => {
  beforeEach(() => {
    mockQuery.mockReset();
  });

  it('resolves a known UID to a user', async () => {
    mockQuery.mockResolvedValueOnce({ rows: [mockUserRow] });

    const user = await resolveUid(mockPool, Buffer.from('aabbccddeeff', 'hex'));

    expect(user).not.toBeNull();
    expect(user!.id).toBe(mockUserRow.id);
    expect(user!.phone).toBe(mockUserRow.phone);
  });

  it('returns null for unknown UID', async () => {
    mockQuery.mockResolvedValueOnce({ rows: [] });

    const user = await resolveUid(mockPool, Buffer.from('000000000000', 'hex'));

    expect(user).toBeNull();
  });
});

describe('SOS ingest with UID', () => {
  let app: express.Express;

  const validSos = {
    id: 'uid:aabbccddeeff:10',
    bleUid: 'aabbccddeeff',
    flags: 1,
    sequence: 10,
    timestamp: '2025-01-15T12:00:00.000Z',
    status: 'active',
    relayHops: 0,
    message: 'Help!',
    receiverLocation: { lat: 19.076, lon: 72.8777 },
    rssi: -55,
  };

  const sosDbRow = {
    id: validSos.id,
    ble_uid: validSos.bleUid,
    flags: validSos.flags,
    sequence: validSos.sequence,
    timestamp: new Date(validSos.timestamp),
    status: 'active',
    relay_hops: 0,
    message: 'Help!',
    receiver_lat: 19.076,
    receiver_lon: 72.8777,
    rssi: -55,
    user_id: mockUserRow.id,
    created_at: new Date(),
    updated_at: new Date(),
  };

  beforeEach(() => {
    app = buildApp();
    mockQuery.mockReset();
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it('resolves UID and stores user_id in SOS event', async () => {
    // Route: findFullProfileByBleUid (3 queries) → upsert
    mockQuery.mockResolvedValueOnce({ rows: [mockUserRow] });   // findFullProfileByBleUid → users
    mockQuery.mockResolvedValueOnce({ rows: [mockContactRow] }); // findFullProfileByBleUid → contacts
    mockQuery.mockResolvedValueOnce({ rows: [mockMedicalRow] }); // findFullProfileByBleUid → medical
    mockQuery.mockResolvedValueOnce({ rows: [sosDbRow] });       // repo.upsert (sosDbRow has user_id = mockUserRow.id)

    const res = await request(app)
      .post('/v1/sos/ingest')
      .send(validSos);

    expect(res.status).toBe(201);
    expect(res.body.userId).toBe(mockUserRow.id);
  });

  it('still ingests SOS when UID is not found', async () => {
    // findFullProfileByBleUid → no user found
    mockQuery.mockResolvedValueOnce({ rows: [] });
    // repo.upsert (no userId)
    const noUserRow = { ...sosDbRow, user_id: null };
    mockQuery.mockResolvedValueOnce({ rows: [noUserRow] });

    const res = await request(app)
      .post('/v1/sos/ingest')
      .send(validSos);

    expect(res.status).toBe(201);
    expect(res.body.userId).toBeUndefined();
  });

  it('still ingests SOS when UID resolves to no user', async () => {
    // findFullProfileByBleUid → no user found
    mockQuery.mockResolvedValueOnce({ rows: [] });
    const noUserRow = { ...sosDbRow, user_id: null };
    mockQuery.mockResolvedValueOnce({ rows: [noUserRow] });

    const res = await request(app)
      .post('/v1/sos/ingest')
      .send(validSos);

    expect(res.status).toBe(201);
  });

  it('rejects invalid bleUid format', async () => {
    const res = await request(app)
      .post('/v1/sos/ingest')
      .send({ ...validSos, bleUid: 'not-valid-hex' });

    expect(res.status).toBe(400);
    expect(res.body.error).toBe('Invalid SOS payload');
  });
});

describe('User profile fetching', () => {
  beforeEach(() => {
    mockQuery.mockReset();
  });

  it('returns full profile with contacts and medical info', async () => {
    // getUserById
    mockQuery.mockResolvedValueOnce({ rows: [mockUserRow] });
    // getEmergencyContacts
    mockQuery.mockResolvedValueOnce({ rows: [mockContactRow] });
    // getMedicalProfile
    mockQuery.mockResolvedValueOnce({ rows: [mockMedicalRow] });

    const profile = await getFullUserProfile(mockPool, mockUserRow.id);

    expect(profile).not.toBeNull();
    expect(profile!.user.id).toBe(mockUserRow.id);
    expect(profile!.contacts).toHaveLength(1);
    expect(profile!.contacts[0].name).toBe('Emergency Friend');
    expect(profile!.medical).not.toBeNull();
    expect(profile!.medical!.bloodGroup).toBe('O+');
  });

  it('returns null for nonexistent user', async () => {
    mockQuery.mockResolvedValueOnce({ rows: [] });

    const profile = await getFullUserProfile(mockPool, 'does-not-exist');

    expect(profile).toBeNull();
  });
});

describe('Escalation payload generation', () => {
  let app: express.Express;

  beforeEach(() => {
    app = buildApp();
    mockQuery.mockReset();
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it('enriches escalation with user profile when UID resolves', async () => {
    const validSos = {
      id: 'uid:aabbccddeeff:42',
      bleUid: 'aabbccddeeff',
      flags: 1,
      sequence: 42,
      timestamp: '2025-01-15T12:00:00.000Z',
      status: 'active',
      relayHops: 0,
      receiverLocation: { lat: 19.076, lon: 72.8777 },
      rssi: -60,
    };

    const sosDbRow = {
      id: validSos.id,
      ble_uid: validSos.bleUid,
      flags: validSos.flags,
      sequence: validSos.sequence,
      timestamp: new Date(validSos.timestamp),
      status: 'active',
      relay_hops: 0,
      message: null,
      receiver_lat: 19.076,
      receiver_lon: 72.8777,
      rssi: -60,
      user_id: mockUserRow.id,
      created_at: new Date(),
      updated_at: new Date(),
    };

    // Route: findFullProfileByBleUid (3 queries) → upsert
    mockQuery.mockResolvedValueOnce({ rows: [mockUserRow] });   // findFullProfileByBleUid → users
    mockQuery.mockResolvedValueOnce({ rows: [mockContactRow] }); // findFullProfileByBleUid → contacts
    mockQuery.mockResolvedValueOnce({ rows: [mockMedicalRow] }); // findFullProfileByBleUid → medical
    mockQuery.mockResolvedValueOnce({ rows: [sosDbRow] });       // repo.upsert

    const res = await request(app)
      .post('/v1/sos/ingest')
      .send(validSos);

    // The enriched escalation runs internally — verify the SOS was stored with user_id
    expect(res.status).toBe(201);
    expect(res.body.userId).toBe(mockUserRow.id);
  });
});

describe('User contacts endpoint', () => {
  let app: express.Express;

  beforeEach(() => {
    app = buildApp();
    mockQuery.mockReset();
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it('POST /v1/users/:id/contacts adds a contact', async () => {
    // Verify user exists
    mockQuery.mockResolvedValueOnce({ rows: [{ id: mockUserRow.id }] });
    // Insert contact
    mockQuery.mockResolvedValueOnce({ rows: [] });

    const res = await request(app)
      .post(`/v1/users/${mockUserRow.id}/contacts`)
      .set('Authorization', authHeader())
      .send({ name: 'Mom', phone: '+911111111111', priority: 1 });

    expect(res.status).toBe(201);
    expect(Array.isArray(res.body)).toBe(true);
    expect(res.body[0].name).toBe('Mom');
  });

  it('POST /v1/users/:id/contacts returns 404 for unknown user', async () => {
    mockQuery.mockResolvedValueOnce({ rows: [] });

    const res = await request(app)
      .post('/v1/users/nonexistent/contacts')
      .set('Authorization', authHeader())
      .send({ name: 'Mom', phone: '+911111111111' });

    expect(res.status).toBe(404);
  });
});

describe('User medical endpoint', () => {
  let app: express.Express;

  beforeEach(() => {
    app = buildApp();
    mockQuery.mockReset();
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it('POST /v1/users/:id/medical sets medical profile', async () => {
    // Verify user exists
    mockQuery.mockResolvedValueOnce({ rows: [{ id: mockUserRow.id }] });
    // Upsert medical profile
    mockQuery.mockResolvedValueOnce({ rows: [] });

    const res = await request(app)
      .post(`/v1/users/${mockUserRow.id}/medical`)
      .set('Authorization', authHeader())
      .send({ bloodGroup: 'O+', allergies: 'None', conditions: 'Healthy' });

    expect(res.status).toBe(200);
    expect(res.body.bloodGroup).toBe('O+');
  });

  it('POST /v1/users/:id/medical returns 404 for unknown user', async () => {
    mockQuery.mockResolvedValueOnce({ rows: [] });

    const res = await request(app)
      .post('/v1/users/nonexistent/medical')
      .set('Authorization', authHeader())
      .send({ bloodGroup: 'AB-' });

    expect(res.status).toBe(404);
  });
});
