/**
 * AfterMath Backend — Onboarding routes.
 *
 * Handles user signup, Aadhaar ZK verification, and profile retrieval.
 *
 * Routes (all under /v1/onboarding):
 *   POST /signup           — Register a new user with basic info + optional contacts & medical
 *   POST /verify-aadhaar   — Submit Aadhaar ZK proof for KYC
 *   GET  /me               — Get current user profile (by JWT)
 *   GET  /status/:userId   — Get onboarding/KYC status for a user
 */

import { Router, type Request, type Response } from 'express';
import type { Pool } from 'pg';
import { signupSchema, aadhaarVerifySchema, aadhaarQrVerifySchema } from '../models/user.js';
import { UserRepository } from '../db/user-repository.js';
import { verifyAadhaarProof, computeExpectedSignalHash } from '../services/aadhaar-zk.js';
import { signToken, requireAuth, optionalAuth } from '../middleware/auth.js';
import { logger } from '../logger.js';

export function createOnboardingRouter(pool: Pool): Router {
  const router = Router();
  const userRepo = new UserRepository(pool);

  // -----------------------------------------------------------------------
  // POST /onboarding/signup
  // -----------------------------------------------------------------------
  //
  // Creates a new user with basic info + optional emergency contacts and
  // medical profile. BLE UID is generated server-side.
  //
  // Returns:
  //  - 201: user created, includes JWT token and BLE UID
  //  - 400: validation error (invalid fields)
  //  - 409: phone already registered
  //
  router.post('/signup', async (req: Request, res: Response) => {
    try {
      const parsed = signupSchema.safeParse(req.body);
      if (!parsed.success) {
        res.status(400).json({
          error: 'Invalid signup payload',
          details: parsed.error.flatten().fieldErrors,
        });
        return;
      }

      const data = parsed.data;

      // Check for existing user by phone
      const existingPhone = await userRepo.findByPhone(data.phone);
      if (existingPhone) {
        res.status(409).json({
          error: 'An account with this phone number already exists',
          field: 'phone',
        });
        return;
      }

      // Create user (BLE UID generated server-side from userId + secret)
      const user = await userRepo.create(data);
      const token = signToken(user.id, user.role);

      // Compute the signal hash the mobile app should use for ZK proof generation.
      // The mobile app converts this userId to a SNARK-compatible BigInt:
      //   signal = BigInt.parse(userId.replaceAll('-', ''), radix: 16)
      // and passes it to generateArgs(..., signal: signal.toString())
      const signalHash = computeExpectedSignalHash(user.id);

      // Optionally create emergency contacts
      let emergencyContacts = null;
      if (data.emergencyContacts && data.emergencyContacts.length > 0) {
        emergencyContacts = await userRepo.createEmergencyContacts(
          user.id,
          data.emergencyContacts,
        );
      }

      // Optionally create medical profile
      let medicalProfile = null;
      if (data.medicalProfile) {
        medicalProfile = await userRepo.upsertMedicalProfile(
          user.id,
          data.medicalProfile,
        );
      }

      logger.info(`Signup: user ${user.id} created (phone: ${user.phone})`);
      res.status(201).json({
        user,
        token,
        signalHash,
        emergencyContacts,
        medicalProfile,
      });
    } catch (err) {
      // Handle unique constraint violations from DB (race condition fallback)
      const pgErr = err as { code?: string; constraint?: string; detail?: string };
      if (pgErr.code === '23505') {
        const detail = pgErr.detail?.toLowerCase() ?? '';
        if (detail.includes('ble_uid')) {
          res.status(409).json({
            error: 'BLE UID collision — please retry',
            field: 'bleUid',
          });
          return;
        }
        res.status(409).json({
          error: 'An account with this phone number already exists',
          field: 'phone',
        });
        return;
      }

      logger.error('Signup error', err);
      res.status(500).json({ error: 'Internal server error' });
    }
  });

  // -----------------------------------------------------------------------
  // POST /onboarding/verify-aadhaar-qr
  // -----------------------------------------------------------------------
  //
  // Lightweight Aadhaar QR XML verification path for onboarding MVP.
  // Parses demographics from the XML and marks user as KYC-verified.
  //
  router.post('/verify-aadhaar-qr', async (req: Request, res: Response) => {
    try {
      const parsed = aadhaarQrVerifySchema.safeParse(req.body);
      if (!parsed.success) {
        res.status(400).json({
          error: 'Invalid Aadhaar QR payload',
          details: parsed.error.flatten().fieldErrors,
        });
        return;
      }

      const data = parsed.data;
      const user = await userRepo.findById(data.userId);
      if (!user) {
        res.status(404).json({ error: 'User not found' });
        return;
      }

      if (user.kycStatus === 'verified') {
        res.status(200).json({
          user,
          message: 'KYC already verified',
        });
        return;
      }

      if (user.kycStatus === 'rejected') {
        res.status(400).json({
          error: 'KYC was previously rejected. Please contact support.',
        });
        return;
      }

      const extracted = parseAadhaarQrXml(data.rawXml);
      const ageAbove18 = computeAgeAbove18(extracted.dob, extracted.yob);

      const updatedUser = await userRepo.updateKycVerifiedFromQr(
        data.userId,
        ageAbove18,
        extracted.gender,
        extracted.state,
      );

      if (!updatedUser) {
        const currentUser = await userRepo.findById(data.userId);
        if (currentUser?.kycStatus === 'verified') {
          res.status(200).json({ user: currentUser, message: 'KYC already verified' });
          return;
        }
        res.status(500).json({ error: 'Failed to update KYC status' });
        return;
      }

      logger.info(`Aadhaar QR verify: user ${data.userId} KYC verified`);
      res.status(200).json({
        user: updatedUser,
        extracted,
        message: 'Aadhaar QR verification successful',
      });
    } catch (err) {
      logger.error('Aadhaar QR verification error', err);
      res.status(422).json({
        error: err instanceof Error ? err.message : 'Invalid Aadhaar QR XML',
      });
    }
  });

  // -----------------------------------------------------------------------
  // POST /onboarding/verify-aadhaar
  // -----------------------------------------------------------------------
  //
  // Accepts a ZK proof from the mobile app's Aadhaar QR scan.
  // Verifies the proof and updates KYC status.
  //
  // Returns:
  //  - 200: KYC verified successfully
  //  - 400: invalid proof payload or verification failure
  //  - 404: user not found
  //  - 409: Aadhaar already used by another account
  //  - 422: proof verification failed (valid format but bad proof)
  //
  router.post('/verify-aadhaar', async (req: Request, res: Response) => {
    try {
      const parsed = aadhaarVerifySchema.safeParse(req.body);
      if (!parsed.success) {
        res.status(400).json({
          error: 'Invalid verification payload',
          details: parsed.error.flatten().fieldErrors,
        });
        return;
      }

      const data = parsed.data;

      // Verify user exists
      const user = await userRepo.findById(data.userId);
      if (!user) {
        res.status(404).json({ error: 'User not found' });
        return;
      }

      // Check if already verified (idempotent)
      if (user.kycStatus === 'verified') {
        logger.info(`Aadhaar verify: user ${data.userId} already verified`);
        res.status(200).json({
          user,
          message: 'KYC already verified',
        });
        return;
      }

      // Check if rejected (must re-register)
      if (user.kycStatus === 'rejected') {
        res.status(400).json({
          error: 'KYC was previously rejected. Please contact support.',
        });
        return;
      }

      // Determine whether to use test or production Aadhaar keys
      const useTestAadhaar = process.env.USE_TEST_AADHAAR === 'true';

      // Run ZK verification pipeline via @anon-aadhaar/core
      const result = await verifyAadhaarProof(
        data.userId,
        data.serializedProof,
        useTestAadhaar,
        userRepo,
      );

      if (!result.valid) {
        // Determine appropriate HTTP status based on error type
        if (result.error?.includes('already been used')) {
          res.status(409).json({ error: result.error });
          return;
        }

        // Log for audit, reject KYC only on definitive proof failure
        // (not on stale timestamp or signal mismatch — those are retryable)
        const errorLower = result.error?.toLowerCase() ?? '';
        const isRetryable = errorLower.includes('too old') ||
                            errorLower.includes('future') ||
                            errorLower.includes('signal');

        if (!isRetryable) {
          await userRepo.updateKycRejected(data.userId);
        }

        res.status(422).json({
          error: result.error,
          retryable: isRetryable ?? false,
        });
        return;
      }

      // Proof valid — update KYC status with extracted demographics
      const demo = result.demographics;
      const updatedUser = await userRepo.updateKycVerified(
        data.userId,
        result.nullifierHash!,
        demo?.ageAbove18 ?? false,
        demo?.gender ?? null,
        demo?.state ?? null,
      );

      if (!updatedUser) {
        // Race condition: KYC status changed between check and update
        const currentUser = await userRepo.findById(data.userId);
        if (currentUser?.kycStatus === 'verified') {
          res.status(200).json({ user: currentUser, message: 'KYC already verified' });
          return;
        }
        res.status(500).json({ error: 'Failed to update KYC status' });
        return;
      }

      logger.info(`Aadhaar verify: user ${data.userId} KYC verified`);
      res.status(200).json({
        user: updatedUser,
        message: 'KYC verification successful',
      });
    } catch (err) {
      logger.error('Aadhaar verification error', err);
      res.status(500).json({ error: 'Internal server error' });
    }
  });

  // -----------------------------------------------------------------------
  // GET /onboarding/me
  // -----------------------------------------------------------------------
  //
  // Returns the authenticated user's profile.
  // Requires a valid JWT token (issued at signup).
  //
  router.get('/me', requireAuth, async (req: Request, res: Response) => {
    try {
      const userId = req.user!.sub;
      const user = await userRepo.findById(userId);

      if (!user) {
        res.status(404).json({ error: 'User not found' });
        return;
      }

      res.status(200).json({ user });
    } catch (err) {
      logger.error('Get profile error', err);
      res.status(500).json({ error: 'Internal server error' });
    }
  });

  // -----------------------------------------------------------------------
  // GET /onboarding/status/:userId
  // -----------------------------------------------------------------------
  //
  // Returns onboarding and KYC status for a user. Does not require auth
  // (the mobile app may call this before the user has a token, using
  // phone number lookup as a fallback).
  //
  // Query params:
  //  - phone (optional): look up by phone number instead of user ID
  //
  router.get('/status/:userId?', optionalAuth, async (req: Request, res: Response) => {
    try {
      let user;

      const paramUserId = req.params.userId;
      if (typeof paramUserId === 'string' && paramUserId.length > 0) {
        user = await userRepo.findById(paramUserId);
      } else if (typeof req.query.phone === 'string') {
        user = await userRepo.findByPhone(req.query.phone);
      } else if (req.user?.sub) {
        user = await userRepo.findById(req.user.sub);
      }

      if (!user) {
        // No user found — fresh device, needs signup
        res.status(200).json({
          onboarded: false,
          kycStatus: null,
          userId: null,
        });
        return;
      }

      res.status(200).json({
        onboarded: true,
        kycStatus: user.kycStatus,
        userId: user.id,
        name: user.name,
        phone: user.phone,
      });
    } catch (err) {
      logger.error('Onboarding status error', err);
      res.status(500).json({ error: 'Internal server error' });
    }
  });

  return router;
}

function parseAadhaarQrXml(raw: string): {
  name: string | null;
  gender: string | null;
  state: string | null;
  dob: string | null;
  yob: string | null;
} {
  const xml = extractXml(raw);
  const nodeMatch = xml.match(/<\s*PrintLetterBarcodeData\b([^>]*)\/?>/i);
  if (!nodeMatch || !nodeMatch[1]) {
    throw new Error('Aadhaar QR XML must contain PrintLetterBarcodeData');
  }

  const attrs = new Map<string, string>();
  const attrRegex = /([a-zA-Z_:][\w:.-]*)\s*=\s*"([^"]*)"/g;
  let m: RegExpExecArray | null;
  while ((m = attrRegex.exec(nodeMatch[1])) !== null) {
    const key = m[1];
    const value = m[2];
    if (!key) continue;
    attrs.set(key.toLowerCase(), decodeXmlEntities(value ?? ''));
  }

  return {
    name: normalizeField(attrs.get('name')),
    gender: normalizeField(attrs.get('gender')),
    state: normalizeField(attrs.get('state')),
    dob: normalizeField(attrs.get('dob')),
    yob: normalizeField(attrs.get('yob')),
  };
}

function computeAgeAbove18(dob: string | null, yob: string | null): boolean {
  const now = new Date();

  if (dob) {
    const parsedDob = parseAadhaarDob(dob);
    if (parsedDob) {
      const eighteenth = new Date(parsedDob);
      eighteenth.setFullYear(eighteenth.getFullYear() + 18);
      return eighteenth <= now;
    }
  }

  if (yob && /^\d{4}$/.test(yob)) {
    return now.getUTCFullYear() - parseInt(yob, 10) >= 18;
  }

  return false;
}

function parseAadhaarDob(dob: string): Date | null {
  const norm = dob.trim();
  let match = norm.match(/^(\d{2})[-/](\d{2})[-/](\d{4})$/);
  if (match) {
    const date = new Date(Date.UTC(Number(match[3]), Number(match[2]) - 1, Number(match[1])));
    return Number.isNaN(date.getTime()) ? null : date;
  }

  match = norm.match(/^(\d{4})[-/](\d{2})[-/](\d{2})$/);
  if (match) {
    const date = new Date(Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3])));
    return Number.isNaN(date.getTime()) ? null : date;
  }

  return null;
}

function extractXml(raw: string): string {
  const trimmed = raw.trim();
  if (trimmed.startsWith('<')) return trimmed;

  try {
    const decoded = decodeURIComponent(trimmed);
    if (decoded.includes('<')) return decoded;
  } catch {
    // Non URI-encoded payload; fall through.
  }

  const start = trimmed.indexOf('<');
  const end = trimmed.lastIndexOf('>');
  if (start >= 0 && end > start) {
    return trimmed.slice(start, end + 1);
  }

  throw new Error('No XML found in QR payload');
}

function decodeXmlEntities(value: string): string {
  return value
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&amp;/g, '&');
}

function normalizeField(value: string | undefined): string | null {
  if (!value) return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}
