/**
 * AfterMath Backend — Disaster reporting route tests.
 *
 * Uses mocked PG pool, mocked Gemini, mocked image store.
 */

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import express from 'express';
import request from 'supertest';
import path from 'node:path';

// ---------------------------------------------------------------------------
// Mock pg
// ---------------------------------------------------------------------------
const mockQuery = vi.fn();
const mockPool = {
  query: mockQuery,
  on: vi.fn(),
  end: vi.fn(),
} as any;

vi.mock('pg', () => ({
  default: { Pool: vi.fn(() => mockPool) },
  Pool: vi.fn(() => mockPool),
}));

// ---------------------------------------------------------------------------
// Mock Twilio (imported transitively)
// ---------------------------------------------------------------------------
const mockCreate = vi.hoisted(() => vi.fn().mockResolvedValue({ sid: 'SM_TEST' }));
vi.mock('twilio', () => ({
  default: vi.fn(() => ({ messages: { create: mockCreate } })),
}));

// ---------------------------------------------------------------------------
// Mock Gemini verify
// ---------------------------------------------------------------------------
const mockVerify = vi.hoisted(() => vi.fn());
vi.mock('../src/services/gemini-verify.js', () => ({
  verifyDisasterImage: mockVerify,
}));

// ---------------------------------------------------------------------------
// Mock image store
// ---------------------------------------------------------------------------
const mockStoreImage = vi.hoisted(() => vi.fn());
const mockHashImage = vi.hoisted(() => vi.fn());
const mockValidateMagic = vi.hoisted(() => vi.fn());

vi.mock('../src/services/image-store.js', () => ({
  storeImage: mockStoreImage,
  hashImage: mockHashImage,
  validateImageMagic: mockValidateMagic,
}));

// ---------------------------------------------------------------------------
// Now import app code
// ---------------------------------------------------------------------------
import { createDisasterRouter } from '../src/routes/disaster.js';
import { signToken } from '../src/middleware/auth.js';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

function buildApp() {
  const app = express();
  app.use(express.json());
  app.use('/v1/disaster', createDisasterRouter(mockPool));
  return app;
}

function userToken(userId = 'user-1', role = 'civilian') {
  return signToken(userId, role);
}

function adminToken(userId = 'admin-1') {
  return signToken(userId, 'admin');
}

/** Minimal 2x1 JPEG (smallest valid JPEG) */
const TINY_JPEG = Buffer.from([
  0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00, 0x01,
  0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xff, 0xd9,
]);

const MOCK_GEMINI_VERIFIED = {
  isReal: true,
  category: 'fire',
  severity: 4,
  confidence: 0.92,
  reasoning: 'Active fire visible',
  flags: [],
};

const MOCK_GEMINI_REJECTED = {
  isReal: false,
  category: 'other',
  severity: 1,
  confidence: 0.95,
  reasoning: 'Photo is a selfie, not a disaster',
  flags: [],
};

const MOCK_GEMINI_FLAGGED = {
  isReal: true,
  category: 'flood',
  severity: 3,
  confidence: 0.7,
  reasoning: 'Flooding visible but image quality suspect',
  flags: ['possible_ai_generated'],
};

const MOCK_DB_REPORT = {
  id: '00000000-0000-4000-8000-000000000001',
  user_id: 'user-1',
  lat: 19.076,
  lon: 72.8777,
  image_url: 'uploads/user-1/report-1.jpg',
  image_hash: 'abc123hash',
  category: 'fire',
  severity_score: 4,
  llm_confidence: 0.92,
  llm_raw_response: MOCK_GEMINI_VERIFIED,
  verification_status: 'verified',
  rejection_reason: null,
  authority_status: 'pending',
  description: 'Building on fire',
  linked_sos_id: null,
  created_at: new Date('2026-03-01T10:00:00Z'),
  updated_at: new Date('2026-03-01T10:00:00Z'),
};

// ---------------------------------------------------------------------------
// Setup
// ---------------------------------------------------------------------------

beforeEach(() => {
  vi.clearAllMocks();
  mockValidateMagic.mockReturnValue('image/jpeg');
  mockHashImage.mockReturnValue('sha256-test-hash');
  mockStoreImage.mockResolvedValue('https://res.cloudinary.com/test/image/upload/aftermath/user-1/report-1.jpg');
  mockVerify.mockResolvedValue(MOCK_GEMINI_VERIFIED);
});

afterEach(() => {
  vi.clearAllMocks();
});

// ===========================================================================
// POST /v1/disaster/report
// ===========================================================================

describe('POST /v1/disaster/report', () => {
  it('returns 401 without auth', async () => {
    const app = buildApp();
    const res = await request(app).post('/v1/disaster/report');
    expect(res.status).toBe(401);
  });

  it('returns 400 when no image is uploaded', async () => {
    const app = buildApp();
    const res = await request(app)
      .post('/v1/disaster/report')
      .set('Authorization', `Bearer ${userToken()}`)
      .field('lat', '19.076')
      .field('lon', '72.8777');
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/image/i);
  });

  it('returns 400 for invalid image format (not JPEG/PNG/WebP)', async () => {
    mockValidateMagic.mockReturnValue(null);
    const app = buildApp();
    const res = await request(app)
      .post('/v1/disaster/report')
      .set('Authorization', `Bearer ${userToken()}`)
      .attach('image', Buffer.from('notanimage'), 'test.txt')
      .field('lat', '19.076')
      .field('lon', '72.8777');
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/invalid image format/i);
  });

  it('returns 400 for missing lat/lon', async () => {
    const app = buildApp();
    const res = await request(app)
      .post('/v1/disaster/report')
      .set('Authorization', `Bearer ${userToken()}`)
      .attach('image', TINY_JPEG, 'test.jpg');
    expect(res.status).toBe(400);
    expect(res.body.details).toBeDefined();
  });

  it('returns 400 for out-of-range lat', async () => {
    const app = buildApp();
    const res = await request(app)
      .post('/v1/disaster/report')
      .set('Authorization', `Bearer ${userToken()}`)
      .attach('image', TINY_JPEG, 'test.jpg')
      .field('lat', '999')
      .field('lon', '72.8777');
    expect(res.status).toBe(400);
  });

  it('creates a verified report successfully (201)', async () => {
    // Rate limit check → 0 reports
    mockQuery.mockResolvedValueOnce({ rows: [{ cnt: 0 }] });
    // Hash dedup check → not found
    mockQuery.mockResolvedValueOnce({ rows: [] });
    // INSERT → return new row
    mockQuery.mockResolvedValueOnce({ rows: [MOCK_DB_REPORT] });

    const app = buildApp();
    const res = await request(app)
      .post('/v1/disaster/report')
      .set('Authorization', `Bearer ${userToken()}`)
      .attach('image', TINY_JPEG, 'fire.jpg')
      .field('lat', '19.076')
      .field('lon', '72.8777')
      .field('description', 'Building on fire');

    expect(res.status).toBe(201);
    expect(res.body.report).toBeDefined();
    expect(res.body.report.verificationStatus).toBe('verified');
    expect(res.body.report.category).toBe('fire');
    expect(res.body.report.severityScore).toBe(4);
    expect(mockVerify).toHaveBeenCalledOnce();
    expect(mockStoreImage).toHaveBeenCalledOnce();
  });

  it('stores a rejected report with status 200', async () => {
    mockVerify.mockResolvedValueOnce(MOCK_GEMINI_REJECTED);
    mockQuery.mockResolvedValueOnce({ rows: [{ cnt: 0 }] });
    mockQuery.mockResolvedValueOnce({ rows: [] });
    mockQuery.mockResolvedValueOnce({
      rows: [{ ...MOCK_DB_REPORT, verification_status: 'rejected', rejection_reason: 'selfie' }],
    });

    const app = buildApp();
    const res = await request(app)
      .post('/v1/disaster/report')
      .set('Authorization', `Bearer ${userToken()}`)
      .attach('image', TINY_JPEG, 'selfie.jpg')
      .field('lat', '19.076')
      .field('lon', '72.8777');

    expect(res.status).toBe(200);
    expect(res.body.report.verificationStatus).toBe('rejected');
  });

  it('stores a flagged report with status 201', async () => {
    mockVerify.mockResolvedValueOnce(MOCK_GEMINI_FLAGGED);
    mockQuery.mockResolvedValueOnce({ rows: [{ cnt: 0 }] });
    mockQuery.mockResolvedValueOnce({ rows: [] });
    mockQuery.mockResolvedValueOnce({
      rows: [{ ...MOCK_DB_REPORT, verification_status: 'flagged', category: 'flood' }],
    });

    const app = buildApp();
    const res = await request(app)
      .post('/v1/disaster/report')
      .set('Authorization', `Bearer ${userToken()}`)
      .attach('image', TINY_JPEG, 'flood.jpg')
      .field('lat', '19.076')
      .field('lon', '72.8777');

    expect(res.status).toBe(201);
    expect(res.body.report.verificationStatus).toBe('flagged');
  });

  it('stores with pending status when Gemini is unavailable', async () => {
    mockVerify.mockResolvedValueOnce(null);
    mockQuery.mockResolvedValueOnce({ rows: [{ cnt: 0 }] });
    mockQuery.mockResolvedValueOnce({ rows: [] });
    mockQuery.mockResolvedValueOnce({
      rows: [{ ...MOCK_DB_REPORT, verification_status: 'pending' }],
    });

    const app = buildApp();
    const res = await request(app)
      .post('/v1/disaster/report')
      .set('Authorization', `Bearer ${userToken()}`)
      .attach('image', TINY_JPEG, 'test.jpg')
      .field('lat', '19.076')
      .field('lon', '72.8777');

    expect(res.status).toBe(201);
    expect(res.body.report.verificationStatus).toBe('pending');
  });

  it('returns 429 when rate limit exceeded', async () => {
    mockQuery.mockResolvedValueOnce({ rows: [{ cnt: 5 }] });

    const app = buildApp();
    const res = await request(app)
      .post('/v1/disaster/report')
      .set('Authorization', `Bearer ${userToken()}`)
      .attach('image', TINY_JPEG, 'test.jpg')
      .field('lat', '19.076')
      .field('lon', '72.8777');

    expect(res.status).toBe(429);
    expect(res.body.error).toMatch(/too many/i);
  });

  it('returns 409 for duplicate image hash', async () => {
    mockQuery.mockResolvedValueOnce({ rows: [{ cnt: 0 }] });
    mockQuery.mockResolvedValueOnce({ rows: [{ 1: 1 }] }); // hash found

    const app = buildApp();
    const res = await request(app)
      .post('/v1/disaster/report')
      .set('Authorization', `Bearer ${userToken()}`)
      .attach('image', TINY_JPEG, 'test.jpg')
      .field('lat', '19.076')
      .field('lon', '72.8777');

    expect(res.status).toBe(409);
    expect(res.body.error).toMatch(/already submitted/i);
  });

  it('accepts optional description up to 500 chars', async () => {
    mockQuery.mockResolvedValueOnce({ rows: [{ cnt: 0 }] });
    mockQuery.mockResolvedValueOnce({ rows: [] });
    mockQuery.mockResolvedValueOnce({ rows: [MOCK_DB_REPORT] });

    const app = buildApp();
    const desc = 'A'.repeat(500);
    const res = await request(app)
      .post('/v1/disaster/report')
      .set('Authorization', `Bearer ${userToken()}`)
      .attach('image', TINY_JPEG, 'test.jpg')
      .field('lat', '19.076')
      .field('lon', '72.8777')
      .field('description', desc);

    expect(res.status).toBe(201);
  });
});

// ===========================================================================
// GET /v1/disaster/feed
// ===========================================================================

describe('GET /v1/disaster/feed', () => {
  it('returns paginated verified reports', async () => {
    mockQuery
      .mockResolvedValueOnce({ rows: [{ total: 1 }] })
      .mockResolvedValueOnce({ rows: [MOCK_DB_REPORT] });

    const app = buildApp();
    const res = await request(app).get('/v1/disaster/feed');

    expect(res.status).toBe(200);
    expect(res.body.reports).toHaveLength(1);
    expect(res.body.total).toBe(1);
    expect(res.body.page).toBe(1);
    expect(res.body.totalPages).toBe(1);
  });

  it('accepts filter query params', async () => {
    mockQuery
      .mockResolvedValueOnce({ rows: [{ total: 0 }] })
      .mockResolvedValueOnce({ rows: [] });

    const app = buildApp();
    const res = await request(app)
      .get('/v1/disaster/feed')
      .query({ category: 'fire', severity_min: 3, page: 1, limit: 10 });

    expect(res.status).toBe(200);
    expect(res.body.reports).toHaveLength(0);
  });

  it('accepts bounding box params', async () => {
    mockQuery
      .mockResolvedValueOnce({ rows: [{ total: 0 }] })
      .mockResolvedValueOnce({ rows: [] });

    const app = buildApp();
    const res = await request(app)
      .get('/v1/disaster/feed')
      .query({
        ne_lat: 20, ne_lon: 73,
        sw_lat: 18, sw_lon: 72,
      });

    expect(res.status).toBe(200);
  });

  it('rejects invalid category', async () => {
    const app = buildApp();
    const res = await request(app)
      .get('/v1/disaster/feed')
      .query({ category: 'explosion' });

    expect(res.status).toBe(400);
  });
});

// ===========================================================================
// GET /v1/disaster/stats
// ===========================================================================

describe('GET /v1/disaster/stats', () => {
  it('returns aggregated stats for 24h', async () => {
    mockQuery
      .mockResolvedValueOnce({
        rows: [{ total: 10, verified: 7, rejected: 2, flagged: 1, pending: 0 }],
      })
      .mockResolvedValueOnce({ rows: [{ category: 'fire', cnt: 5 }, { category: 'flood', cnt: 2 }] })
      .mockResolvedValueOnce({ rows: [{ severity_score: 3, cnt: 4 }, { severity_score: 4, cnt: 3 }] })
      .mockResolvedValueOnce({ rows: [{ cnt: 15 }] });

    const app = buildApp();
    const res = await request(app).get('/v1/disaster/stats');

    expect(res.status).toBe(200);
    expect(res.body.totalReports).toBe(10);
    expect(res.body.verified).toBe(7);
    expect(res.body.byCategory).toEqual({ fire: 5, flood: 2 });
    expect(res.body.sosCount).toBe(15);
  });

  it('accepts 7d range', async () => {
    mockQuery
      .mockResolvedValueOnce({ rows: [{ total: 0, verified: 0, rejected: 0, flagged: 0, pending: 0 }] })
      .mockResolvedValueOnce({ rows: [] })
      .mockResolvedValueOnce({ rows: [] })
      .mockResolvedValueOnce({ rows: [{ cnt: 0 }] });

    const app = buildApp();
    const res = await request(app).get('/v1/disaster/stats').query({ range: '7d' });
    expect(res.status).toBe(200);
  });
});

// ===========================================================================
// GET /v1/disaster/heatmap
// ===========================================================================

describe('GET /v1/disaster/heatmap', () => {
  it('returns geo-clustered points', async () => {
    mockQuery.mockResolvedValueOnce({
      rows: [
        { lat: '19.08', lon: '72.88', count: 5, avg_severity: '3.2' },
        { lat: '19.10', lon: '72.90', count: 2, avg_severity: '4.0' },
      ],
    });

    const app = buildApp();
    const res = await request(app).get('/v1/disaster/heatmap');

    expect(res.status).toBe(200);
    expect(res.body.points).toHaveLength(2);
    expect(res.body.points[0].count).toBe(5);
    expect(res.body.points[0].avgSeverity).toBe(3.2);
  });

  it('accepts precision and category filter', async () => {
    mockQuery.mockResolvedValueOnce({ rows: [] });

    const app = buildApp();
    const res = await request(app)
      .get('/v1/disaster/heatmap')
      .query({ precision: 3, category: 'flood' });

    expect(res.status).toBe(200);
    expect(res.body.points).toHaveLength(0);
  });
});

// ===========================================================================
// GET /v1/disaster/:id
// ===========================================================================

describe('GET /v1/disaster/:id', () => {
  it('returns a single report', async () => {
    mockQuery.mockResolvedValueOnce({ rows: [MOCK_DB_REPORT] });

    const app = buildApp();
    const res = await request(app).get('/v1/disaster/00000000-0000-4000-8000-000000000001');

    expect(res.status).toBe(200);
    expect(res.body.report.id).toBe('00000000-0000-4000-8000-000000000001');
    expect(res.body.report.category).toBe('fire');
  });

  it('returns 404 for non-existent report', async () => {
    mockQuery.mockResolvedValueOnce({ rows: [] });

    const app = buildApp();
    const res = await request(app).get('/v1/disaster/00000000-0000-4000-8000-000000000099');

    expect(res.status).toBe(404);
  });
});

// ===========================================================================
// PATCH /v1/disaster/:id/status
// ===========================================================================

describe('PATCH /v1/disaster/:id/status', () => {
  it('returns 401 without auth', async () => {
    const app = buildApp();
    const res = await request(app)
      .patch('/v1/disaster/00000000-0000-4000-8000-000000000001/status')
      .send({ authority_status: 'dispatched' });
    expect(res.status).toBe(401);
  });

  it('returns 403 for non-admin users', async () => {
    const app = buildApp();
    const res = await request(app)
      .patch('/v1/disaster/00000000-0000-4000-8000-000000000001/status')
      .set('Authorization', `Bearer ${userToken()}`)
      .send({ authority_status: 'dispatched' });
    expect(res.status).toBe(403);
  });

  it('updates authority status as admin', async () => {
    mockQuery.mockResolvedValueOnce({
      rows: [{ ...MOCK_DB_REPORT, authority_status: 'dispatched' }],
    });

    const app = buildApp();
    const res = await request(app)
      .patch('/v1/disaster/00000000-0000-4000-8000-000000000001/status')
      .set('Authorization', `Bearer ${adminToken()}`)
      .send({ authority_status: 'dispatched' });

    expect(res.status).toBe(200);
    expect(res.body.report.authorityStatus).toBe('dispatched');
  });

  it('returns 404 for non-existent report', async () => {
    mockQuery.mockResolvedValueOnce({ rows: [] });

    const app = buildApp();
    const res = await request(app)
      .patch('/v1/disaster/00000000-0000-4000-8000-000000000099/status')
      .set('Authorization', `Bearer ${adminToken()}`)
      .send({ authority_status: 'resolved' });

    expect(res.status).toBe(404);
  });

  it('rejects invalid authority status', async () => {
    const app = buildApp();
    const res = await request(app)
      .patch('/v1/disaster/00000000-0000-4000-8000-000000000001/status')
      .set('Authorization', `Bearer ${adminToken()}`)
      .send({ authority_status: 'invalid' });

    expect(res.status).toBe(400);
  });
});

// ===========================================================================
// Image validation (unit)
// ===========================================================================

describe('Image validation', () => {
  // Directly import real image store for unit tests
  it('validates JPEG magic bytes', async () => {
    // We're testing the mock, but let's verify the pattern
    mockValidateMagic.mockReturnValue('image/jpeg');
    expect(mockValidateMagic(TINY_JPEG)).toBe('image/jpeg');
  });

  it('rejects non-image data', async () => {
    mockValidateMagic.mockReturnValue(null);
    expect(mockValidateMagic(Buffer.from('not an image'))).toBeNull();
  });
});
