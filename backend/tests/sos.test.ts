/**
 * AfterMath Backend — SOS route tests (V2 privacy-first protocol).
 *
 * Uses a mocked PG pool so tests run entirely in-memory without a real database.
 */

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import express from 'express';
import request from 'supertest';

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

// Expose mockCreate so escalation tests can assert on SMS call counts.
// vi.hoisted ensures the value is available inside the vi.mock factory.
const mockCreate = vi.hoisted(() => vi.fn().mockResolvedValue({ sid: 'SM_TEST' }));

// Mock Twilio so it doesn't try to connect
vi.mock('twilio', () => {
  return {
    default: vi.fn(() => ({
      messages: { create: mockCreate },
    })),
  };
});

// Now safe to import
import { createSosRouter } from '../src/routes/sos.js';
import { createHealthRouter } from '../src/routes/health.js';
import { createAuthRouter } from '../src/routes/auth.js';
import { signToken } from '../src/middleware/auth.js';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function buildApp() {
  const app = express();
  app.use(express.json());
  app.use('/v1/health', createHealthRouter(mockPool));
  app.use('/v1/auth', createAuthRouter());
  app.use('/v1/sos', createSosRouter(mockPool));
  return app;
}

/** V2 payload — bleUid hex, receiver location, no deviceIdHash/lat/lon. */
const validSos = {
  id: 'uid:aabbccddee01:42',
  bleUid: 'aabbccddee01',
  flags: 1,
  sequence: 42,
  timestamp: '2025-01-15T12:00:00.000Z',
  status: 'active',
  relayHops: 0,
  receiverLocation: { lat: 19.076, lon: 72.8777 },
  rssi: -65,
  message: 'Help!',
};

/** Simulated DB row returned by mock pool.query. */
const dbRow = {
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
  rssi: -65,
  user_id: null,
  created_at: new Date(),
  updated_at: new Date(),
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('Health route', () => {
  const app = buildApp();

  it('GET /v1/health returns 200 when DB is reachable', async () => {
    mockQuery.mockResolvedValueOnce({ rows: [{ '?column?': 1 }] });
    const res = await request(app).get('/v1/health');
    expect(res.status).toBe(200);
    expect(res.body.status).toBe('ok');
  });

  it('GET /v1/health returns 503 when DB is down', async () => {
    mockQuery.mockRejectedValueOnce(new Error('connection refused'));
    const res = await request(app).get('/v1/health');
    expect(res.status).toBe(503);
    expect(res.body.status).toBe('unhealthy');
  });
});

describe('Auth route', () => {
  const app = buildApp();

  it('POST /v1/auth/token issues a JWT', async () => {
    const res = await request(app)
      .post('/v1/auth/token')
      .send({ sub: 'user-123', role: 'responder' });
    expect(res.status).toBe(200);
    expect(res.body).toHaveProperty('token');
    expect(res.body.expiresIn).toBe('1h');
  });

  it('POST /v1/auth/token rejects missing sub', async () => {
    const res = await request(app)
      .post('/v1/auth/token')
      .send({ role: 'responder' });
    expect(res.status).toBe(400);
  });
});

describe('SOS routes', () => {
  let app: express.Express;

  beforeEach(() => {
    app = buildApp();
    mockQuery.mockReset();
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  // -------------------------------------------------------------------------
  // POST /v1/sos/ingest
  // -------------------------------------------------------------------------

  describe('POST /v1/sos/ingest', () => {
    it('returns 201 with valid V2 SOS payload', async () => {
      // 1st call: UID resolution (no match)
      mockQuery.mockResolvedValueOnce({ rows: [] });
      // 2nd call: upsert
      mockQuery.mockResolvedValueOnce({ rows: [dbRow] });

      const res = await request(app)
        .post('/v1/sos/ingest')
        .send(validSos);

      expect(res.status).toBe(201);
      expect(res.body.id).toBe(validSos.id);
      expect(res.body.bleUid).toBe(validSos.bleUid);
      expect(res.body.flags).toBe(validSos.flags);
      expect(res.body.sequence).toBe(validSos.sequence);
      expect(res.body.status).toBe('active');
      expect(res.body.receiverLat).toBe(19.076);
      expect(res.body.receiverLon).toBe(72.8777);
      expect(res.body.rssi).toBe(-65);
    });

    it('returns 400 for missing required fields', async () => {
      const res = await request(app)
        .post('/v1/sos/ingest')
        .send({ id: 'x' });

      expect(res.status).toBe(400);
      expect(res.body.error).toBe('Invalid SOS payload');
    });

    it('returns 400 for invalid bleUid (wrong length)', async () => {
      const res = await request(app)
        .post('/v1/sos/ingest')
        .send({ ...validSos, bleUid: 'aabb' });

      expect(res.status).toBe(400);
    });

    it('returns 400 for invalid bleUid (non-hex)', async () => {
      const res = await request(app)
        .post('/v1/sos/ingest')
        .send({ ...validSos, bleUid: 'zzzzzzzzzzzz' });

      expect(res.status).toBe(400);
    });

    it('returns 400 for message exceeding 64 chars', async () => {
      const res = await request(app)
        .post('/v1/sos/ingest')
        .send({ ...validSos, message: 'x'.repeat(65) });

      expect(res.status).toBe(400);
    });

    it('works without optional message field', async () => {
      const { message: _, ...noMsg } = validSos;
      const row = { ...dbRow, message: null };
      mockQuery.mockResolvedValueOnce({ rows: [] }); // UID resolution
      mockQuery.mockResolvedValueOnce({ rows: [row] });

      const res = await request(app)
        .post('/v1/sos/ingest')
        .send(noMsg);

      expect(res.status).toBe(201);
      expect(res.body.message).toBeUndefined();
    });

    it('works without optional receiverLocation', async () => {
      const { receiverLocation: _, ...noLoc } = validSos;
      const row = { ...dbRow, receiver_lat: null, receiver_lon: null };
      mockQuery.mockResolvedValueOnce({ rows: [] }); // UID resolution
      mockQuery.mockResolvedValueOnce({ rows: [row] });

      const res = await request(app)
        .post('/v1/sos/ingest')
        .send(noLoc);

      expect(res.status).toBe(201);
      expect(res.body.receiverLat).toBeUndefined();
    });

    it('accepts request with Bearer token', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [] }); // UID resolution
      mockQuery.mockResolvedValueOnce({ rows: [dbRow] });
      const token = signToken('user-1', 'responder');

      const res = await request(app)
        .post('/v1/sos/ingest')
        .set('Authorization', `Bearer ${token}`)
        .send(validSos);

      expect(res.status).toBe(201);
    });
  });

  // -------------------------------------------------------------------------
  // POST /v1/sos/acknowledge
  // -------------------------------------------------------------------------

  describe('POST /v1/sos/acknowledge', () => {
    it('returns 200 when SOS exists and is active', async () => {
      const ackRow = { ...dbRow, status: 'acknowledged' };
      mockQuery.mockResolvedValueOnce({ rows: [ackRow] });

      const res = await request(app)
        .post('/v1/sos/acknowledge')
        .send({ id: validSos.id });

      expect(res.status).toBe(200);
      expect(res.body.status).toBe('acknowledged');
    });

    it('returns 404 when SOS does not exist', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [] });

      const res = await request(app)
        .post('/v1/sos/acknowledge')
        .send({ id: 'nonexistent' });

      expect(res.status).toBe(404);
    });

    it('returns 400 for missing id', async () => {
      const res = await request(app)
        .post('/v1/sos/acknowledge')
        .send({});

      expect(res.status).toBe(400);
    });
  });

  // -------------------------------------------------------------------------
  // GET /v1/sos/active
  // -------------------------------------------------------------------------

  describe('GET /v1/sos/active', () => {
    it('returns array of active events', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [dbRow] });

      const res = await request(app).get('/v1/sos/active');

      expect(res.status).toBe(200);
      expect(Array.isArray(res.body)).toBe(true);
      expect(res.body).toHaveLength(1);
      expect(res.body[0].id).toBe(validSos.id);
      expect(res.body[0].bleUid).toBe(validSos.bleUid);
    });

    it('returns empty array when no active events', async () => {
      mockQuery.mockResolvedValueOnce({ rows: [] });

      const res = await request(app).get('/v1/sos/active');

      expect(res.status).toBe(200);
      expect(res.body).toEqual([]);
    });
  });
});

describe('SOS model validation', () => {
  it('rejects invalid status values', async () => {
    const app = buildApp();
    const res = await request(app)
      .post('/v1/sos/ingest')
      .send({ ...validSos, status: 'invalid_status' });

    expect(res.status).toBe(400);
  });

  it('rejects negative relayHops', async () => {
    const app = buildApp();
    const res = await request(app)
      .post('/v1/sos/ingest')
      .send({ ...validSos, relayHops: -1 });

    expect(res.status).toBe(400);
  });

  it('accepts all valid SOS statuses', async () => {
    const app = buildApp();
    const statuses = ['active', 'relayed', 'acknowledged', 'resolved', 'cancelled'];

    for (const status of statuses) {
      mockQuery.mockResolvedValueOnce({ rows: [] }); // UID resolution
      mockQuery.mockResolvedValueOnce({ rows: [{ ...dbRow, status }] });
      const res = await request(app)
        .post('/v1/sos/ingest')
        .send({ ...validSos, id: `test-${status}`, status });

      expect(res.status).toBe(201);
    }
  });

  it('rejects sequence > 255', async () => {
    const app = buildApp();
    const res = await request(app)
      .post('/v1/sos/ingest')
      .send({ ...validSos, sequence: 256 });

    expect(res.status).toBe(400);
  });

  it('rejects flags > 255', async () => {
    const app = buildApp();
    const res = await request(app)
      .post('/v1/sos/ingest')
      .send({ ...validSos, flags: 256 });

    expect(res.status).toBe(400);
  });
});

describe('Escalation timer', () => {
  it('starts timer on active SOS ingest', async () => {
    const app = buildApp();
    mockQuery.mockResolvedValueOnce({ rows: [] }); // UID resolution
    mockQuery.mockResolvedValueOnce({ rows: [dbRow] });

    const res = await request(app)
      .post('/v1/sos/ingest')
      .send(validSos);

    expect(res.status).toBe(201);
    // Timer is started internally — we verify by checking no crash
  });

  it('cancels timer on acknowledge', async () => {
    const app = buildApp();
    // First ingest
    mockQuery.mockResolvedValueOnce({ rows: [] }); // UID resolution
    mockQuery.mockResolvedValueOnce({ rows: [dbRow] });
    await request(app).post('/v1/sos/ingest').send(validSos);

    // Then acknowledge
    const ackRow = { ...dbRow, status: 'acknowledged' };
    mockQuery.mockResolvedValueOnce({ rows: [ackRow] });
    const res = await request(app)
      .post('/v1/sos/acknowledge')
      .send({ id: validSos.id });

    expect(res.status).toBe(200);
  });

  it('immediately sends distress SMS to emergency contacts on ingest', async () => {
    const app = buildApp();
    mockQuery.mockReset();
    mockCreate.mockClear();

    const userRow = {
      id: 'u-esc-1',
      name: 'Victim Name',
      phone: '+919999999998',
      ble_uid: Buffer.from(validSos.bleUid, 'hex'),
      language: 'en',
      created_at: new Date(),
    };
    const contactRow1 = { id: 'c-1', user_id: 'u-esc-1', name: 'Mom', phone: '+911111111111', priority: 1 };
    const contactRow2 = { id: 'c-2', user_id: 'u-esc-1', name: 'Dad', phone: '+912222222222', priority: 2 };
    const dbRowWithUser = { ...dbRow, user_id: 'u-esc-1' };

    mockQuery.mockResolvedValueOnce({ rows: [userRow] });                   // resolveUid
    mockQuery.mockResolvedValueOnce({ rows: [dbRowWithUser] });             // upsert
    mockQuery.mockResolvedValueOnce({ rows: [userRow] });                   // getUserById (profile enrichment)
    mockQuery.mockResolvedValueOnce({ rows: [contactRow1, contactRow2] }); // getEmergencyContacts
    mockQuery.mockResolvedValueOnce({ rows: [] });                          // getMedicalProfile

    const res = await request(app).post('/v1/sos/ingest').send(validSos);
    expect(res.status).toBe(201);

    // Allow the fire-and-forget Promise.allSettled to settle
    await new Promise((r) => setTimeout(r, 10));

    // Both emergency contacts should have received an immediate SMS
    const destinations = mockCreate.mock.calls.map((c: any[]) => c[0].to as string);
    expect(destinations).toContain('+911111111111'); // Mom
    expect(destinations).toContain('+912222222222'); // Dad
  });
});
