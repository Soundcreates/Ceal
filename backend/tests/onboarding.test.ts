/**
 * AfterMath Backend — Onboarding route tests.
 *
 * Tests cover:
 *  - Signup validation (phone, name, language, contacts, medical)
 *  - Duplicate detection (phone)
 *  - Emergency contacts & medical profile creation during signup
 *  - Aadhaar ZK verification flow (via mocked @anon-aadhaar/core)
 *  - Profile retrieval (authenticated & by phone)
 *  - Onboarding status endpoint
 *  - Error handling & edge cases
 *
 * Uses a mocked PG pool — no real database required.
 * Uses mocked @anon-aadhaar/core — no real ZK operations.
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

// Mock Twilio so it doesn't try to connect
vi.mock('twilio', () => {
  const create = vi.fn().mockResolvedValue({ sid: 'SM_TEST' });
  return {
    default: vi.fn(() => ({
      messages: { create },
    })),
  };
});

// ---------------------------------------------------------------------------
// Mock @anon-aadhaar/core BEFORE importing anything that uses it
// ---------------------------------------------------------------------------
const { mockInit, mockVerify, mockDeserialize, mockHash } = vi.hoisted(() => ({
  mockInit: vi.fn().mockResolvedValue(undefined),
  mockVerify: vi.fn().mockResolvedValue(true),
  mockDeserialize: vi.fn(),
  mockHash: vi.fn().mockReturnValue('expected-signal-hash'),
}));

vi.mock('@anon-aadhaar/core', () => ({
  init: mockInit,
  verify: mockVerify,
  deserialize: mockDeserialize,
  hash: mockHash,
  artifactUrls: {
    v2: {
      wasm: 'https://test-wasm-url',
      zkey: 'https://test-zkey-url',
      vk: 'https://test-vk-url',
    },
  },
  ArtifactsOrigin: { server: 0, local: 1, chunked: 2 },
}));

// Now safe to import
import { createOnboardingRouter } from '../src/routes/onboarding.js';
import { signToken } from '../src/middleware/auth.js';
import { computeExpectedSignalHash, _internal, _resetInit } from '../src/services/aadhaar-zk.js';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function buildApp() {
  const app = express();
  app.use(express.json());
  app.use('/v1/onboarding', createOnboardingRouter(mockPool));
  return app;
}

const validSignup = {
  name: 'Aarav Patel',
  phone: '+919876543210',
  language: 'en',
};

const validSignupWithExtras = {
  ...validSignup,
  emergencyContacts: [
    { name: 'Mom', phone: '+919876543211', priority: 1 },
    { name: 'Dad', phone: '+919876543212', priority: 2 },
  ],
  medicalProfile: {
    bloodGroup: 'O+',
    allergies: 'Peanuts',
    conditions: 'Asthma',
  },
};

const userId = '660e8400-e29b-41d4-a716-446655440001';
const testNullifier = 'abc123def456789nullifier';
const testTimestamp = String(Math.floor(Date.now() / 1000)); // Unix seconds

function makeUserDbRow(overrides: Record<string, unknown> = {}) {
  return {
    id: userId,
    name: validSignup.name,
    phone: validSignup.phone,
    ble_uid: Buffer.from('aabbccddeeff', 'hex'),
    language: 'en',
    role: 'civilian',
    kyc_status: 'pending',
    aadhaar_nullifier: null,
    aadhaar_verified_at: null,
    aadhaar_age_above_18: null,
    aadhaar_gender: null,
    aadhaar_state: null,
    created_at: new Date(),
    updated_at: new Date(),
    ...overrides,
  };
}

/**
 * Build a mock AnonAadhaarCore object that mockDeserialize will return.
 * This shape matches the real @anon-aadhaar/core's AnonAadhaarCore class.
 */
function makeMockPcd(overrides: {
  nullifier?: string;
  signalHash?: string;
  timestamp?: string;
  ageAbove18?: boolean | null;
  gender?: string | null;
  state?: string | null;
  pincode?: string | null;
} = {}) {
  const sigHash = 'signalHash' in overrides ? overrides.signalHash! : 'expected-signal-hash';
  const age18 = 'ageAbove18' in overrides ? overrides.ageAbove18 : true;
  const gender = 'gender' in overrides ? overrides.gender : 'M';
  const state = 'state' in overrides ? overrides.state : 'MH';
  const pincode = 'pincode' in overrides ? overrides.pincode : '40';
  return {
    id: 'test-proof-id',
    type: 'anon-aadhaar',
    claim: {
      pubKey: ['123', '456'],
      signalHash: sigHash,
      ageAbove18: age18,
      gender: gender,
      state: state,
      pincode: pincode,
    },
    proof: {
      groth16Proof: {
        pi_a: ['1', '2', '1'],
        pi_b: [['3', '4'], ['5', '6'], ['1', '0']],
        pi_c: ['7', '8', '1'],
        protocol: 'groth16',
        curve: 'bn128',
      },
      pubkeyHash: 'test-pubkey-hash',
      timestamp: overrides.timestamp ?? testTimestamp,
      nullifierSeed: '1234',
      nullifier: overrides.nullifier ?? testNullifier,
      signalHash: sigHash,
      ageAbove18: age18 ? '1' : '0',
      gender: '77',  // encoded
      pincode: '0',
      state: '0',
    },
  };
}

function makeValidAadhaarPayload() {
  return {
    userId,
    serializedProof: JSON.stringify(makeMockPcd()),
  };
}

/**
 * Setup the mock deserialize to return a proper PCD object.
 * Call this in beforeEach when testing aadhaar verification.
 */
function setupMockDeserialize(pcd = makeMockPcd()) {
  mockDeserialize.mockResolvedValue(pcd);
}

// ---------------------------------------------------------------------------
// Tests — Signup
// ---------------------------------------------------------------------------

describe('POST /v1/onboarding/signup', () => {
  let app: express.Express;

  beforeEach(() => {
    app = buildApp();
    mockQuery.mockReset();
    mockHash.mockReset().mockReturnValue('expected-signal-hash');
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it('creates a user and returns 201 with valid payload', async () => {
    // findByPhone → no rows
    mockQuery.mockResolvedValueOnce({ rows: [] });
    // INSERT → returns user
    mockQuery.mockResolvedValueOnce({ rows: [makeUserDbRow()] });

    const res = await request(app)
      .post('/v1/onboarding/signup')
      .send(validSignup);

    expect(res.status).toBe(201);
    expect(res.body.user).toBeDefined();
    expect(res.body.user.name).toBe(validSignup.name);
    expect(res.body.user.phone).toBe(validSignup.phone);
    expect(res.body.user.bleUid).toBeDefined();
    expect(res.body.user.language).toBe('en');
    expect(res.body.user.kycStatus).toBe('pending');
    expect(res.body.token).toBeDefined();
    expect(typeof res.body.token).toBe('string');
    expect(res.body.signalHash).toBeDefined();
    expect(res.body.signalHash).toBe(computeExpectedSignalHash(userId));
    // No contacts/medical by default
    expect(res.body.emergencyContacts).toBeNull();
    expect(res.body.medicalProfile).toBeNull();
  });

  it('creates user with emergency contacts and medical profile', async () => {
    // findByPhone → no rows
    mockQuery.mockResolvedValueOnce({ rows: [] });
    // INSERT user → returns user
    mockQuery.mockResolvedValueOnce({ rows: [makeUserDbRow()] });
    // INSERT contact 1
    mockQuery.mockResolvedValueOnce({ rows: [] });
    // INSERT contact 2
    mockQuery.mockResolvedValueOnce({ rows: [] });
    // UPSERT medical profile
    mockQuery.mockResolvedValueOnce({ rows: [] });

    const res = await request(app)
      .post('/v1/onboarding/signup')
      .send(validSignupWithExtras);

    expect(res.status).toBe(201);
    expect(res.body.user.name).toBe(validSignup.name);
    expect(res.body.emergencyContacts).toHaveLength(2);
    expect(res.body.emergencyContacts[0].name).toBe('Mom');
    expect(res.body.emergencyContacts[0].phone).toBe('+919876543211');
    expect(res.body.emergencyContacts[0].priority).toBe(1);
    expect(res.body.emergencyContacts[1].name).toBe('Dad');
    expect(res.body.medicalProfile).toBeDefined();
    expect(res.body.medicalProfile.bloodGroup).toBe('O+');
    expect(res.body.medicalProfile.allergies).toBe('Peanuts');
    expect(res.body.medicalProfile.conditions).toBe('Asthma');
  });

  it('creates user with optional name omitted', async () => {
    mockQuery.mockResolvedValueOnce({ rows: [] }); // findByPhone
    mockQuery.mockResolvedValueOnce({
      rows: [makeUserDbRow({ name: null })],
    });

    const res = await request(app)
      .post('/v1/onboarding/signup')
      .send({ phone: '+919876543210' }); // name omitted, language defaults

    expect(res.status).toBe(201);
    expect(res.body.user.name).toBeNull();
    expect(res.body.user.language).toBe('en');
  });

  it('returns 409 for duplicate phone', async () => {
    // findByPhone → returns existing user
    mockQuery.mockResolvedValueOnce({ rows: [makeUserDbRow()] });

    const res = await request(app)
      .post('/v1/onboarding/signup')
      .send(validSignup);

    expect(res.status).toBe(409);
    expect(res.body.error).toContain('phone');
    expect(res.body.field).toBe('phone');
  });

  it('handles PG unique constraint violation gracefully (race condition)', async () => {
    mockQuery.mockResolvedValueOnce({ rows: [] }); // findByPhone
    // INSERT fails with unique violation
    mockQuery.mockRejectedValueOnce({
      code: '23505',
      constraint: 'users_phone_key',
      detail: 'Key (phone)=(+919876543210) already exists.',
    });

    const res = await request(app)
      .post('/v1/onboarding/signup')
      .send(validSignup);

    expect(res.status).toBe(409);
    expect(res.body.field).toBe('phone');
  });

  it('handles BLE UID constraint violation (extremely rare)', async () => {
    mockQuery.mockResolvedValueOnce({ rows: [] }); // findByPhone
    mockQuery.mockRejectedValueOnce({
      code: '23505',
      constraint: 'users_ble_uid_key',
      detail: 'Key (ble_uid) already exists.',
    });

    const res = await request(app)
      .post('/v1/onboarding/signup')
      .send(validSignup);

    expect(res.status).toBe(409);
    expect(res.body.field).toBe('bleUid');
    expect(res.body.error).toContain('BLE UID');
  });

  // --- Validation errors ---

  it('returns 400 for missing phone', async () => {
    const res = await request(app)
      .post('/v1/onboarding/signup')
      .send({ name: 'Test' });

    expect(res.status).toBe(400);
    expect(res.body.details.phone).toBeDefined();
  });

  it('returns 400 for phone without E.164 format', async () => {
    const res = await request(app)
      .post('/v1/onboarding/signup')
      .send({ ...validSignup, phone: '9876543210' }); // missing +

    expect(res.status).toBe(400);
    expect(res.body.details.phone).toBeDefined();
  });

  it('returns 400 for phone too short', async () => {
    const res = await request(app)
      .post('/v1/onboarding/signup')
      .send({ ...validSignup, phone: '+123' });

    expect(res.status).toBe(400);
  });

  it('returns 400 for name too short (if provided)', async () => {
    const res = await request(app)
      .post('/v1/onboarding/signup')
      .send({ ...validSignup, name: 'A' });

    expect(res.status).toBe(400);
    expect(res.body.details.name).toBeDefined();
  });

  it('returns 400 for empty body', async () => {
    const res = await request(app)
      .post('/v1/onboarding/signup')
      .send({});

    expect(res.status).toBe(400);
  });

  it('returns 400 for invalid emergency contact (missing phone)', async () => {
    const res = await request(app)
      .post('/v1/onboarding/signup')
      .send({
        ...validSignup,
        emergencyContacts: [{ name: 'Mom' }], // missing phone
      });

    expect(res.status).toBe(400);
  });

  it('returns 400 for too many emergency contacts', async () => {
    const tooMany = Array.from({ length: 11 }, (_, i) => ({
      phone: `+91900000000${i}`,
      priority: i + 1,
    }));
    const res = await request(app)
      .post('/v1/onboarding/signup')
      .send({ ...validSignup, emergencyContacts: tooMany });

    expect(res.status).toBe(400);
  });

  it('trims whitespace from name', async () => {
    mockQuery.mockResolvedValueOnce({ rows: [] }); // findByPhone
    mockQuery.mockResolvedValueOnce({ rows: [makeUserDbRow({ name: 'Aarav Patel' })] });

    const res = await request(app)
      .post('/v1/onboarding/signup')
      .send({ ...validSignup, name: '  Aarav Patel  ' });

    expect(res.status).toBe(201);
    // Verify the INSERT was called with trimmed name
    const insertCall = mockQuery.mock.calls[1];
    expect(insertCall[1][1]).toBe('Aarav Patel');
  });

  it('defaults language to "en" when not provided', async () => {
    mockQuery.mockResolvedValueOnce({ rows: [] }); // findByPhone
    mockQuery.mockResolvedValueOnce({ rows: [makeUserDbRow()] });

    const res = await request(app)
      .post('/v1/onboarding/signup')
      .send({ phone: '+919876543210' });

    expect(res.status).toBe(201);
    // Verify INSERT was called with 'en' as language
    // Params: [id, name, phone, ble_uid, language] → language is index 4
    const insertCall = mockQuery.mock.calls[1];
    expect(insertCall[1][4]).toBe('en');
  });
});

// ---------------------------------------------------------------------------
// Tests — Aadhaar ZK Verification
// ---------------------------------------------------------------------------

describe('POST /v1/onboarding/verify-aadhaar', () => {
  let app: express.Express;

  beforeEach(() => {
    app = buildApp();
    mockQuery.mockReset();
    mockVerify.mockReset().mockResolvedValue(true);
    mockDeserialize.mockReset();
    mockHash.mockReset().mockReturnValue('expected-signal-hash');
    _resetInit();
    setupMockDeserialize();
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it('verifies Aadhaar proof and returns 200 with valid payload', async () => {
    const aadhaarPayload = makeValidAadhaarPayload();

    // findById → returns pending user
    mockQuery.mockResolvedValueOnce({ rows: [makeUserDbRow()] });
    // findByNullifier → no existing
    mockQuery.mockResolvedValueOnce({ rows: [] });
    // updateKycVerified → returns updated user
    mockQuery.mockResolvedValueOnce({
      rows: [makeUserDbRow({
        kyc_status: 'verified',
        aadhaar_nullifier: testNullifier,
        aadhaar_verified_at: new Date(),
        aadhaar_age_above_18: true,
        aadhaar_gender: 'M',
        aadhaar_state: 'MH',
      })],
    });

    const res = await request(app)
      .post('/v1/onboarding/verify-aadhaar')
      .send(aadhaarPayload);

    expect(res.status).toBe(200);
    expect(res.body.user.kycStatus).toBe('verified');
    expect(res.body.message).toContain('successful');
    // Verify @anon-aadhaar/core functions were called
    expect(mockDeserialize).toHaveBeenCalledWith(aadhaarPayload.serializedProof);
    expect(mockVerify).toHaveBeenCalled();
    expect(mockInit).toHaveBeenCalled();
  });

  it('returns 200 idempotently if user already verified', async () => {
    const aadhaarPayload = makeValidAadhaarPayload();

    // findById → returns already verified user
    mockQuery.mockResolvedValueOnce({
      rows: [makeUserDbRow({ kyc_status: 'verified' })],
    });

    const res = await request(app)
      .post('/v1/onboarding/verify-aadhaar')
      .send(aadhaarPayload);

    expect(res.status).toBe(200);
    expect(res.body.message).toContain('already verified');
  });

  it('returns 400 if user KYC was previously rejected', async () => {
    const aadhaarPayload = makeValidAadhaarPayload();

    // findById → returns rejected user
    mockQuery.mockResolvedValueOnce({
      rows: [makeUserDbRow({ kyc_status: 'rejected' })],
    });

    const res = await request(app)
      .post('/v1/onboarding/verify-aadhaar')
      .send(aadhaarPayload);

    expect(res.status).toBe(400);
    expect(res.body.error).toContain('rejected');
  });

  it('returns 404 if user does not exist', async () => {
    const aadhaarPayload = makeValidAadhaarPayload();

    // findById → no rows
    mockQuery.mockResolvedValueOnce({ rows: [] });

    const res = await request(app)
      .post('/v1/onboarding/verify-aadhaar')
      .send(aadhaarPayload);

    expect(res.status).toBe(404);
    expect(res.body.error).toContain('not found');
  });

  it('returns 409 if nullifier already used by another user', async () => {
    const aadhaarPayload = makeValidAadhaarPayload();
    const otherUserId = '770e8400-e29b-41d4-a716-446655440002';

    // findById → returns pending user
    mockQuery.mockResolvedValueOnce({ rows: [makeUserDbRow()] });
    // findByNullifier → returns different user
    mockQuery.mockResolvedValueOnce({
      rows: [makeUserDbRow({ id: otherUserId })],
    });

    const res = await request(app)
      .post('/v1/onboarding/verify-aadhaar')
      .send(aadhaarPayload);

    expect(res.status).toBe(409);
    expect(res.body.error).toContain('already been used');
  });

  it('returns 200 idempotently when same user resubmits same nullifier', async () => {
    const aadhaarPayload = makeValidAadhaarPayload();

    // findById → returns pending user
    mockQuery.mockResolvedValueOnce({ rows: [makeUserDbRow()] });
    // findByNullifier → returns same user (already verified this nullifier)
    mockQuery.mockResolvedValueOnce({
      rows: [makeUserDbRow({ id: userId, aadhaar_nullifier: testNullifier })],
    });
    // updateKycVerified is still called
    mockQuery.mockResolvedValueOnce({
      rows: [makeUserDbRow({
        kyc_status: 'verified',
        aadhaar_nullifier: testNullifier,
      })],
    });

    const res = await request(app)
      .post('/v1/onboarding/verify-aadhaar')
      .send(aadhaarPayload);

    expect(res.status).toBe(200);
  });

  it('returns 422 with wrong signal binding', async () => {
    // Setup deserialize to return PCD with wrong signalHash
    setupMockDeserialize(makeMockPcd({ signalHash: 'wrong-signal-hash' }));
    const aadhaarPayload = makeValidAadhaarPayload();

    // findById → returns pending user
    mockQuery.mockResolvedValueOnce({ rows: [makeUserDbRow()] });

    const res = await request(app)
      .post('/v1/onboarding/verify-aadhaar')
      .send(aadhaarPayload);

    expect(res.status).toBe(422);
    expect(res.body.error).toContain('Signal');
    expect(res.body.retryable).toBe(true);
  });

  it('returns 422 with expired timestamp', async () => {
    // Set timestamp to 20 minutes ago (beyond 15 min limit)
    const oldTimestamp = String(Math.floor(Date.now() / 1000) - 20 * 60);
    setupMockDeserialize(makeMockPcd({ timestamp: oldTimestamp }));
    const aadhaarPayload = makeValidAadhaarPayload();

    // findById → returns pending user
    mockQuery.mockResolvedValueOnce({ rows: [makeUserDbRow()] });

    const res = await request(app)
      .post('/v1/onboarding/verify-aadhaar')
      .send(aadhaarPayload);

    expect(res.status).toBe(422);
    expect(res.body.error).toContain('too old');
    expect(res.body.retryable).toBe(true);
  });

  it('returns 422 with future timestamp', async () => {
    // Set timestamp to 5 minutes in the future
    const futureTimestamp = String(Math.floor(Date.now() / 1000) + 5 * 60);
    setupMockDeserialize(makeMockPcd({ timestamp: futureTimestamp }));
    const aadhaarPayload = makeValidAadhaarPayload();

    // findById → returns pending user
    mockQuery.mockResolvedValueOnce({ rows: [makeUserDbRow()] });

    const res = await request(app)
      .post('/v1/onboarding/verify-aadhaar')
      .send(aadhaarPayload);

    expect(res.status).toBe(422);
    expect(res.body.error).toContain('future');
    expect(res.body.retryable).toBe(true);
  });

  it('returns 422 when verify() returns false (invalid ZK proof)', async () => {
    mockVerify.mockResolvedValueOnce(false);
    const aadhaarPayload = makeValidAadhaarPayload();

    // findById → returns pending user
    mockQuery.mockResolvedValueOnce({ rows: [makeUserDbRow()] });
    // findByNullifier → no existing
    mockQuery.mockResolvedValueOnce({ rows: [] });
    // updateKycRejected → non-retryable failure
    mockQuery.mockResolvedValueOnce({
      rows: [makeUserDbRow({ kyc_status: 'rejected' })],
    });

    const res = await request(app)
      .post('/v1/onboarding/verify-aadhaar')
      .send(aadhaarPayload);

    expect(res.status).toBe(422);
    expect(res.body.error).toContain('invalid ZK proof');
    expect(res.body.retryable).toBe(false);
  });

  it('returns 422 when verify() throws (e.g. public key mismatch)', async () => {
    mockVerify.mockRejectedValueOnce(new Error('VerificationError: public key mismatch.'));
    const aadhaarPayload = makeValidAadhaarPayload();

    // findById → returns pending user
    mockQuery.mockResolvedValueOnce({ rows: [makeUserDbRow()] });
    // findByNullifier → no existing
    mockQuery.mockResolvedValueOnce({ rows: [] });
    // updateKycRejected
    mockQuery.mockResolvedValueOnce({
      rows: [makeUserDbRow({ kyc_status: 'rejected' })],
    });

    const res = await request(app)
      .post('/v1/onboarding/verify-aadhaar')
      .send(aadhaarPayload);

    expect(res.status).toBe(422);
    expect(res.body.error).toContain('public key mismatch');
    expect(res.body.retryable).toBe(false);
  });

  it('returns 422 when deserialize fails (invalid proof format)', async () => {
    mockDeserialize.mockRejectedValueOnce(new Error('Unexpected token'));
    const aadhaarPayload = makeValidAadhaarPayload();

    // findById → returns pending user
    mockQuery.mockResolvedValueOnce({ rows: [makeUserDbRow()] });
    // updateKycRejected (non-retryable deserialization failure)
    mockQuery.mockResolvedValueOnce({
      rows: [makeUserDbRow({ kyc_status: 'rejected' })],
    });

    const res = await request(app)
      .post('/v1/onboarding/verify-aadhaar')
      .send(aadhaarPayload);

    expect(res.status).toBe(422);
    expect(res.body.error).toContain('deserialize');
    expect(res.body.retryable).toBe(false);
  });

  it('extracts demographics from verified proof claim', async () => {
    setupMockDeserialize(makeMockPcd({
      ageAbove18: true,
      gender: 'F',
      state: 'KA',
      pincode: '56',
    }));
    const aadhaarPayload = makeValidAadhaarPayload();

    // findById → returns pending user
    mockQuery.mockResolvedValueOnce({ rows: [makeUserDbRow()] });
    // findByNullifier → no existing
    mockQuery.mockResolvedValueOnce({ rows: [] });
    // updateKycVerified
    mockQuery.mockResolvedValueOnce({
      rows: [makeUserDbRow({
        kyc_status: 'verified',
        aadhaar_nullifier: testNullifier,
        aadhaar_age_above_18: true,
        aadhaar_gender: 'F',
        aadhaar_state: 'KA',
      })],
    });

    const res = await request(app)
      .post('/v1/onboarding/verify-aadhaar')
      .send(aadhaarPayload);

    expect(res.status).toBe(200);
    // Verify the updateKycVerified was called with demographics from the proof
    const updateCall = mockQuery.mock.calls.find((call: any[]) =>
      typeof call[0] === 'string' && call[0].includes('kyc_status'));
    expect(updateCall).toBeDefined();
  });

  // --- Validation errors ---

  it('returns 400 for missing userId', async () => {
    const res = await request(app)
      .post('/v1/onboarding/verify-aadhaar')
      .send({ serializedProof: 'some-proof' });

    expect(res.status).toBe(400);
  });

  it('returns 400 for invalid userId format', async () => {
    const res = await request(app)
      .post('/v1/onboarding/verify-aadhaar')
      .send({ userId: 'not-a-uuid', serializedProof: 'some-proof' });

    expect(res.status).toBe(400);
  });

  it('returns 400 for missing serializedProof', async () => {
    const res = await request(app)
      .post('/v1/onboarding/verify-aadhaar')
      .send({ userId });

    expect(res.status).toBe(400);
  });

  it('returns 400 for empty serializedProof', async () => {
    const res = await request(app)
      .post('/v1/onboarding/verify-aadhaar')
      .send({ userId, serializedProof: '' });

    expect(res.status).toBe(400);
  });
});

// ---------------------------------------------------------------------------
// Tests — GET /me
// ---------------------------------------------------------------------------

describe('GET /v1/onboarding/me', () => {
  let app: express.Express;

  beforeEach(() => {
    app = buildApp();
    mockQuery.mockReset();
  });

  it('returns user profile with valid JWT', async () => {
    const token = signToken(userId, 'civilian');
    mockQuery.mockResolvedValueOnce({ rows: [makeUserDbRow()] });

    const res = await request(app)
      .get('/v1/onboarding/me')
      .set('Authorization', `Bearer ${token}`);

    expect(res.status).toBe(200);
    expect(res.body.user.id).toBe(userId);
    expect(res.body.user.name).toBe(validSignup.name);
    expect(res.body.user.phone).toBe(validSignup.phone);
    expect(res.body.user.bleUid).toBeDefined();
  });

  it('returns 401 without JWT', async () => {
    const res = await request(app).get('/v1/onboarding/me');

    expect(res.status).toBe(401);
  });

  it('returns 401 with invalid JWT', async () => {
    const res = await request(app)
      .get('/v1/onboarding/me')
      .set('Authorization', 'Bearer invalid-token');

    expect(res.status).toBe(401);
  });

  it('returns 404 if user deleted/not found', async () => {
    const token = signToken(userId, 'civilian');
    mockQuery.mockResolvedValueOnce({ rows: [] });

    const res = await request(app)
      .get('/v1/onboarding/me')
      .set('Authorization', `Bearer ${token}`);

    expect(res.status).toBe(404);
  });
});

// ---------------------------------------------------------------------------
// Tests — GET /status
// ---------------------------------------------------------------------------

describe('GET /v1/onboarding/status', () => {
  let app: express.Express;

  beforeEach(() => {
    app = buildApp();
    mockQuery.mockReset();
  });

  it('returns onboarded=false for unknown user ID', async () => {
    mockQuery.mockResolvedValueOnce({ rows: [] });

    const res = await request(app)
      .get(`/v1/onboarding/status/${userId}`);

    expect(res.status).toBe(200);
    expect(res.body.onboarded).toBe(false);
    expect(res.body.userId).toBeNull();
  });

  it('returns status for known user ID', async () => {
    mockQuery.mockResolvedValueOnce({
      rows: [makeUserDbRow({ kyc_status: 'verified' })],
    });

    const res = await request(app)
      .get(`/v1/onboarding/status/${userId}`);

    expect(res.status).toBe(200);
    expect(res.body.onboarded).toBe(true);
    expect(res.body.kycStatus).toBe('verified');
    expect(res.body.userId).toBe(userId);
    expect(res.body.name).toBe(validSignup.name);
    expect(res.body.phone).toBe(validSignup.phone);
  });

  it('looks up by phone query param when no userId in path', async () => {
    mockQuery.mockResolvedValueOnce({
      rows: [makeUserDbRow()],
    });

    const res = await request(app)
      .get(`/v1/onboarding/status?phone=${encodeURIComponent(validSignup.phone)}`);

    expect(res.status).toBe(200);
    expect(res.body.onboarded).toBe(true);
    expect(res.body.userId).toBe(userId);
  });

  it('uses JWT sub when no userId and no phone', async () => {
    const token = signToken(userId, 'civilian');
    mockQuery.mockResolvedValueOnce({
      rows: [makeUserDbRow()],
    });

    const res = await request(app)
      .get('/v1/onboarding/status')
      .set('Authorization', `Bearer ${token}`);

    expect(res.status).toBe(200);
    expect(res.body.onboarded).toBe(true);
  });

  it('returns onboarded=false when no identifier provided and no JWT', async () => {
    const res = await request(app).get('/v1/onboarding/status');

    expect(res.status).toBe(200);
    expect(res.body.onboarded).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// Tests — ZK Verification Service (unit tests)
// ---------------------------------------------------------------------------

describe('Aadhaar ZK verification service internals', () => {
  beforeEach(() => {
    mockHash.mockReset().mockReturnValue('expected-signal-hash');
  });

  describe('validateTimestamp', () => {
    it('accepts recent timestamp (Unix seconds)', () => {
      const nowSec = String(Math.floor(Date.now() / 1000));
      const result = _internal.validateTimestamp(nowSec);
      expect(result.valid).toBe(true);
    });

    it('rejects timestamp older than 15 minutes', () => {
      const oldSec = String(Math.floor(Date.now() / 1000) - 20 * 60);
      const result = _internal.validateTimestamp(oldSec);
      expect(result.valid).toBe(false);
      expect(result.error).toContain('too old');
    });

    it('rejects timestamp more than 1 minute in the future', () => {
      const futureSec = String(Math.floor(Date.now() / 1000) + 2 * 60);
      const result = _internal.validateTimestamp(futureSec);
      expect(result.valid).toBe(false);
      expect(result.error).toContain('future');
    });

    it('accepts timestamp slightly in the future (clock skew tolerance)', () => {
      const slightFutureSec = String(Math.floor(Date.now() / 1000) + 30);
      const result = _internal.validateTimestamp(slightFutureSec);
      expect(result.valid).toBe(true);
    });

    it('rejects invalid timestamp string', () => {
      const result = _internal.validateTimestamp('not-a-number');
      expect(result.valid).toBe(false);
      expect(result.error).toContain('Invalid timestamp');
    });

    it('rejects zero timestamp', () => {
      const result = _internal.validateTimestamp('0');
      expect(result.valid).toBe(false);
    });

    it('rejects negative timestamp', () => {
      const result = _internal.validateTimestamp('-100');
      expect(result.valid).toBe(false);
    });
  });

  describe('validateSignalBinding', () => {
    it('accepts correct signal hash for user', () => {
      // mockHash returns 'expected-signal-hash' for any input
      const result = _internal.validateSignalBinding('expected-signal-hash', userId);
      expect(result.valid).toBe(true);
      expect(mockHash).toHaveBeenCalled();
    });

    it('rejects wrong signal hash', () => {
      const result = _internal.validateSignalBinding('wrong-hash', userId);
      expect(result.valid).toBe(false);
      expect(result.error).toContain('Signal');
    });

    it('rejects signal generated for different user', () => {
      // First call returns hash for userId, but we compare against different hash
      mockHash.mockReturnValueOnce('hash-for-other-user');
      const result = _internal.validateSignalBinding('expected-signal-hash', userId);
      expect(result.valid).toBe(false);
    });
  });

  describe('computeExpectedSignalHash', () => {
    it('calls hash() with BigInt derived from UUID', () => {
      const result = computeExpectedSignalHash(userId);
      expect(result).toBe('expected-signal-hash');
      expect(mockHash).toHaveBeenCalledWith(
        BigInt('0x' + userId.replace(/-/g, '')),
      );
    });

    it('produces same result for same userId', () => {
      const s1 = computeExpectedSignalHash(userId);
      const s2 = computeExpectedSignalHash(userId);
      expect(s1).toBe(s2);
    });
  });

  describe('extractDemographics', () => {
    it('extracts demographics from PCD claim', () => {
      const pcd = makeMockPcd({
        ageAbove18: true,
        gender: 'F',
        state: 'KA',
        pincode: '56',
      });
      const demo = _internal.extractDemographics(pcd);
      expect(demo).toEqual({
        ageAbove18: true,
        gender: 'F',
        state: 'KA',
        pincode: '56',
      });
    });

    it('handles null/undefined demographics gracefully', () => {
      const pcd = makeMockPcd({
        ageAbove18: null,
        gender: null,
        state: null,
        pincode: null,
      });
      const demo = _internal.extractDemographics(pcd);
      expect(demo).toEqual({
        ageAbove18: null,
        gender: null,
        state: null,
        pincode: null,
      });
    });
  });
});

// ---------------------------------------------------------------------------
// Tests — Full onboarding flow (integration-style)
// ---------------------------------------------------------------------------

describe('Full onboarding flow', () => {
  let app: express.Express;

  beforeEach(() => {
    app = buildApp();
    mockQuery.mockReset();
    mockVerify.mockReset().mockResolvedValue(true);
    mockDeserialize.mockReset();
    mockHash.mockReset().mockReturnValue('expected-signal-hash');
    _resetInit();
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  it('signup → verify-aadhaar → me (complete happy path)', async () => {
    // ── Step 1: Signup with contacts & medical ──
    mockQuery.mockResolvedValueOnce({ rows: [] }); // findByPhone
    mockQuery.mockResolvedValueOnce({ rows: [makeUserDbRow()] }); // INSERT user
    mockQuery.mockResolvedValueOnce({ rows: [] }); // INSERT contact 1
    mockQuery.mockResolvedValueOnce({ rows: [] }); // INSERT contact 2
    mockQuery.mockResolvedValueOnce({ rows: [] }); // UPSERT medical

    const signupRes = await request(app)
      .post('/v1/onboarding/signup')
      .send(validSignupWithExtras);

    expect(signupRes.status).toBe(201);
    const { token, signalHash } = signupRes.body;
    expect(token).toBeDefined();
    expect(signalHash).toBeDefined();
    expect(signupRes.body.emergencyContacts).toHaveLength(2);
    expect(signupRes.body.medicalProfile.bloodGroup).toBe('O+');

    // ── Step 2: Verify Aadhaar ──
    // Setup mock deserialize to return PCD with matching signalHash
    setupMockDeserialize(makeMockPcd({
      ageAbove18: true,
      gender: 'F',
      state: 'KA',
    }));

    const aadhaarPayload = {
      userId,
      serializedProof: JSON.stringify(makeMockPcd({
        ageAbove18: true,
        gender: 'F',
        state: 'KA',
      })),
    };

    // findById → pending user
    mockQuery.mockResolvedValueOnce({ rows: [makeUserDbRow()] });
    // findByNullifier → no existing
    mockQuery.mockResolvedValueOnce({ rows: [] });
    // updateKycVerified → returns verified user
    const verifiedRow = makeUserDbRow({
      kyc_status: 'verified',
      aadhaar_nullifier: testNullifier,
      aadhaar_verified_at: new Date(),
      aadhaar_age_above_18: true,
      aadhaar_gender: 'F',
      aadhaar_state: 'KA',
    });
    mockQuery.mockResolvedValueOnce({ rows: [verifiedRow] });

    const verifyRes = await request(app)
      .post('/v1/onboarding/verify-aadhaar')
      .send(aadhaarPayload);

    expect(verifyRes.status).toBe(200);
    expect(verifyRes.body.user.kycStatus).toBe('verified');

    // Verify @anon-aadhaar/core was used
    expect(mockDeserialize).toHaveBeenCalled();
    expect(mockVerify).toHaveBeenCalled();

    // ── Step 3: Get profile ──
    mockQuery.mockResolvedValueOnce({ rows: [verifiedRow] });

    const meRes = await request(app)
      .get('/v1/onboarding/me')
      .set('Authorization', `Bearer ${token}`);

    expect(meRes.status).toBe(200);
    expect(meRes.body.user.kycStatus).toBe('verified');
    expect(meRes.body.user.aadhaarGender).toBe('F');
    expect(meRes.body.user.aadhaarState).toBe('KA');
  });

  it('signup (minimal) → verify-aadhaar (minimal happy path)', async () => {
    // ── Step 1: Minimal signup (phone only) ──
    mockQuery.mockResolvedValueOnce({ rows: [] }); // findByPhone
    mockQuery.mockResolvedValueOnce({
      rows: [makeUserDbRow({ name: null })],
    }); // INSERT user

    const signupRes = await request(app)
      .post('/v1/onboarding/signup')
      .send({ phone: '+919876543210' });

    expect(signupRes.status).toBe(201);
    expect(signupRes.body.emergencyContacts).toBeNull();
    expect(signupRes.body.medicalProfile).toBeNull();

    // ── Step 2: Verify Aadhaar ──
    setupMockDeserialize(makeMockPcd());

    mockQuery.mockResolvedValueOnce({ rows: [makeUserDbRow({ name: null })] }); // findById
    mockQuery.mockResolvedValueOnce({ rows: [] }); // findByNullifier
    mockQuery.mockResolvedValueOnce({
      rows: [makeUserDbRow({ name: null, kyc_status: 'verified', aadhaar_nullifier: testNullifier })],
    }); // updateKycVerified

    const verifyRes = await request(app)
      .post('/v1/onboarding/verify-aadhaar')
      .send(makeValidAadhaarPayload());

    expect(verifyRes.status).toBe(200);
    expect(verifyRes.body.user.kycStatus).toBe('verified');
  });
});
