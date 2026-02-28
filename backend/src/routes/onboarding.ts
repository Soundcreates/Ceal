/**
 * CEAL Backend — Onboarding routes.
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
import {
  signupSchema,
  aadhaarVerifySchema,
  aadhaarQrVerifySchema,
  manualKycSchema,
} from '../models/user.js';
import { UserRepository } from '../db/user-repository.js';
import { verifyAadhaarProof, computeExpectedSignalHash } from '../services/aadhaar-zk.js';
import { signToken, requireAuth, optionalAuth } from '../middleware/auth.js';
import { logger } from '../logger.js';
import { randomUUID, createHash } from 'node:crypto';
import { z } from 'zod';
import { decodeQrFromRgba, parseAadhaarQrPayload } from '../services/aadhaar-qr-photo.js';

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
  // POST /onboarding/scan-aadhaar-photo
  // -----------------------------------------------------------------------
  //
  // TS-native photo QR flow:
  // - accepts JSON upload from mobile (`rgbaBase64`, `width`, `height`, `userId`)
  // - decodes QR with jsQR
  // - parses Aadhaar payload (Self SDK adapter + XML fallback)
  // - stores scan artifact + marks KYC verified
  //
  router.post('/scan-aadhaar-photo', async (req: Request, res: Response) => {
    try {
      const inputCheck = z.object({
        userId: z.string().uuid('Invalid user ID'),
        width: z.number().int().positive().max(4096),
        height: z.number().int().positive().max(4096),
        rgbaBase64: z.string().min(1, 'RGBA image payload is required'),
        source: z.string().max(50).default('photo'),
      }).safeParse(req.body);
      if (!inputCheck.success) {
        res.status(400).json({
          error: 'Invalid Aadhaar photo payload',
          details: inputCheck.error.flatten().fieldErrors,
        });
        return;
      }

      const user = await userRepo.findById(inputCheck.data.userId);
      if (!user) {
        res.status(404).json({ error: 'User not found' });
        return;
      }

      const rgbaBuffer = decodeBase64(inputCheck.data.rgbaBase64);
      const expectedLen = inputCheck.data.width * inputCheck.data.height * 4;
      if (rgbaBuffer.length !== expectedLen) {
        res.status(400).json({
          error: `Invalid RGBA payload size: expected ${expectedLen} bytes, got ${rgbaBuffer.length}`,
        });
        return;
      }

      const decoded = decodeQrFromRgba(
        inputCheck.data.width,
        inputCheck.data.height,
        new Uint8ClampedArray(rgbaBuffer.buffer, rgbaBuffer.byteOffset, rgbaBuffer.byteLength),
      );
      const extracted = await parseAadhaarQrPayload(decoded.rawPayload);
      const imageSha256 = createHash('sha256').update(rgbaBuffer).digest('hex');

      await pool.query(
        `INSERT INTO aadhaar_qr_scans (id, user_id, source, image_sha256, image_data, decoded_xml, processed_by)
         VALUES ($1, $2, $3, $4, $5, $6, $7)`,
        [
          randomUUID(),
          inputCheck.data.userId,
          inputCheck.data.source,
          imageSha256,
          rgbaBuffer,
          decoded.rawPayload,
          'ts-backend-jsqr',
        ],
      );

      if (user.kycStatus === 'verified') {
        res.status(200).json({ user, extracted, message: 'Scan stored; KYC already verified' });
        return;
      }
      if (user.kycStatus === 'rejected') {
        res.status(400).json({
          error: 'KYC was previously rejected. Please contact support.',
        });
        return;
      }

      const ageAbove18 = computeAgeAbove18(extracted.dob, extracted.yob);
      const updatedUser = await userRepo.updateKycVerifiedFromQr(
        inputCheck.data.userId,
        ageAbove18,
        extracted.gender,
        extracted.state,
      );

      if (!updatedUser) {
        const currentUser = await userRepo.findById(inputCheck.data.userId);
        if (currentUser?.kycStatus === 'verified') {
          res.status(200).json({ user: currentUser, extracted, message: 'Scan stored; KYC already verified' });
          return;
        }
        res.status(500).json({ error: 'Scan stored but failed to update KYC status' });
        return;
      }

      logger.info(`Aadhaar photo scan: user ${inputCheck.data.userId} KYC verified`);
      res.status(200).json({
        user: updatedUser,
        extracted,
        decodedXml: decoded.rawPayload,
        message: 'Aadhaar photo processed and stored successfully',
      });
    } catch (err) {
      logger.error('Aadhaar photo scan error', err);
      const message = err instanceof Error ? err.message : 'Internal server error';
      const status = message.includes('No QR code detected') ? 422 : 500;
      res.status(status).json({ error: message });
    }
  });

  // -----------------------------------------------------------------------
  // POST /onboarding/manual-kyc
  // -----------------------------------------------------------------------
  //
  // Manual fallback when Aadhaar scan is skipped.
  // Persists submitted details for audit/manual review.
  //
  router.post('/manual-kyc', async (req: Request, res: Response) => {
    try {
      const parsed = manualKycSchema.safeParse(req.body);
      if (!parsed.success) {
        res.status(400).json({
          error: 'Invalid manual KYC payload',
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

      await userRepo.saveManualKycSubmission(data);
      const updated = await userRepo.updateUserFromManualKyc(
        data.userId,
        data.name,
        data.age >= 18,
        data.sex,
        data.state,
      );

      logger.info(`Manual KYC submitted: user ${data.userId}`);
      res.status(200).json({
        user: updated ?? user,
        message: 'Manual KYC details saved successfully',
      });
    } catch (err) {
      logger.error('Manual KYC submission error', err);
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

      const extracted = await parseAadhaarQrPayload(data.rawXml);
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

function decodeBase64(value: string): Buffer {
  const cleaned = value.replace(/^data:[^;]+;base64,/, '');
  const out = Buffer.from(cleaned, 'base64');
  if (out.length === 0) {
    throw new Error('Image payload is empty');
  }
  return out;
}
