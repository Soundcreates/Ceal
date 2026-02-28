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
import { signupSchema, aadhaarVerifySchema } from '../models/user.js';
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

      if (req.params.userId) {
        user = await userRepo.findById(req.params.userId);
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
