/**
 * CEAL Backend — Aadhaar Zero-Knowledge Verification Service.
 *
 * Uses @anon-aadhaar/core to verify ZK-SNARK proofs generated from
 * Aadhaar QR code scans on the mobile app.
 *
 * ──────────────────────────────────────────────────────────────────────
 * PROTOCOL OVERVIEW
 * ──────────────────────────────────────────────────────────────────────
 *
 * 1. The mobile app scans the Aadhaar QR code (UIDAI-signed data).
 *
 * 2. The app generates a ZK-SNARK proof (Groth16 over BN254) using
 *    @anon-aadhaar/core's `prove()` function. The proof attests:
 *    a) The user possesses a QR code signed by UIDAI's RSA public key
 *    b) A nullifier hash is derived deterministically from the Aadhaar
 *       number + nullifier seed, preventing double-registration
 *    c) Demographic signals (age > 18, gender, state, pincode) are
 *       selectively disclosed without revealing the full Aadhaar data
 *    d) A signal hash binds the proof to a specific user/session
 *
 * 3. The app serializes the proof via `serialize()` and sends the
 *    serialized PCD string to the backend.
 *
 * 4. The backend:
 *    a) Deserializes the PCD → AnonAadhaarCore object
 *    b) Validates the timestamp is recent (replay protection)
 *    c) Validates the signal binding (proof is for this user)
 *    d) Checks nullifier uniqueness (prevents double-KYC)
 *    e) Cryptographically verifies the proof via `verify()`
 *
 * ──────────────────────────────────────────────────────────────────────
 * SECURITY MODEL
 * ──────────────────────────────────────────────────────────────────────
 *
 * - UIDAI's RSA-2048 public key hash is embedded in the circuit
 * - @anon-aadhaar/core handles Groth16 pairing verification via snarkjs
 * - Nullifier uniqueness prevents Sybil attacks via Aadhaar reuse
 * - Signal binding prevents proof portability between users
 * - Timestamp check prevents replay of old proofs
 * - The actual Aadhaar number NEVER reaches the backend
 */

import {
  init,
  verify,
  deserialize,
  hash,
  artifactUrls,
  ArtifactsOrigin,
} from '@anon-aadhaar/core';
import type { InitArgs } from '@anon-aadhaar/core';
import { logger } from '../logger.js';
import type { UserRepository } from '../db/user-repository.js';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/** Maximum age of a proof timestamp (seconds since epoch) before it's stale. */
const MAX_PROOF_AGE_S = 15 * 60; // 15 minutes

/** Clock skew tolerance — allow timestamps up to 60s in the future. */
const FUTURE_TOLERANCE_S = 60;

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface ZkVerificationResult {
  valid: boolean;
  error?: string;
  nullifierHash?: string;
  /** Demographics extracted from the verified proof's claim. */
  demographics?: {
    ageAbove18: boolean | null;
    gender: string | null;
    state: string | null;
    pincode: string | null;
  };
}

// ---------------------------------------------------------------------------
// Initialization
// ---------------------------------------------------------------------------

let initialized = false;

/**
 * Initialize the @anon-aadhaar/core package.
 *
 * Must be called once before any verification. Idempotent — safe to
 * call multiple times. Stores artifact URLs for the Groth16 verification
 * key that `verify()` fetches on first use.
 */
export async function initAnonAadhaar(): Promise<void> {
  if (initialized) return;

  const initArgs: InitArgs = {
    wasmURL: artifactUrls.v2.wasm,
    zkeyURL: artifactUrls.v2.zkey,
    vkeyURL: artifactUrls.v2.vk,
    artifactsOrigin: ArtifactsOrigin.server,
  };

  await init(initArgs);
  initialized = true;
  logger.info('Anon Aadhaar core initialized (vkey will be fetched on first verify)');
}

/**
 * Reset initialization state. Used for testing only.
 * @internal
 */
export function _resetInit(): void {
  initialized = false;
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Full verification pipeline for an Aadhaar ZK proof submission.
 *
 * @param userId - The UUID of the user submitting the proof
 * @param serializedProof - The serialized PCD string from the mobile app
 *   (the `pcd` field from `serialize()` in @anon-aadhaar/core)
 * @param useTestAadhaar - If true, verify against the test UIDAI public key
 * @param userRepo - User repository for nullifier uniqueness checks
 */
export async function verifyAadhaarProof(
  userId: string,
  serializedProof: string,
  useTestAadhaar: boolean,
  userRepo: UserRepository,
): Promise<ZkVerificationResult> {
  // Ensure the library is initialized
  await initAnonAadhaar();

  // Step 1: Deserialize the proof PCD
  let pcd: Awaited<ReturnType<typeof deserialize>>;
  try {
    pcd = await deserialize(serializedProof);
  } catch (err) {
    const msg = err instanceof Error ? err.message : 'unknown error';
    logger.warn(`Aadhaar ZK: failed to deserialize proof for user ${userId}: ${msg}`);
    return { valid: false, error: 'Failed to deserialize proof — invalid format' };
  }

  // Step 2: Validate timestamp freshness
  // @anon-aadhaar/core stores timestamp as a Unix timestamp string (seconds)
  const timestampCheck = validateTimestamp(pcd.proof.timestamp);
  if (!timestampCheck.valid) {
    logger.warn(`Aadhaar ZK: timestamp invalid for user ${userId}: ${timestampCheck.error}`);
    return timestampCheck;
  }

  // Step 3: Validate signal binding
  // The mobile app generates the proof with signal = userId (converted to
  // a SNARK-compatible BigInt). We verify that the proof's signalHash
  // matches what we expect for this userId.
  const signalCheck = validateSignalBinding(pcd.proof.signalHash, userId);
  if (!signalCheck.valid) {
    logger.warn(`Aadhaar ZK: signal binding failed for user ${userId}: ${signalCheck.error}`);
    return signalCheck;
  }

  // Step 4: Check nullifier uniqueness — prevent double-KYC
  const nullifier = pcd.proof.nullifier;
  const existingUser = await userRepo.findByNullifier(nullifier);
  if (existingUser) {
    if (existingUser.id === userId) {
      // Same user re-submitting — idempotent
      logger.info(`Aadhaar ZK: user ${userId} already verified with this nullifier`);
      return { valid: true, nullifierHash: nullifier, demographics: extractDemographics(pcd) };
    }
    // Different user trying to reuse the same Aadhaar
    logger.warn(`Aadhaar ZK: nullifier collision — user ${userId} tried nullifier owned by ${existingUser.id}`);
    return { valid: false, error: 'This Aadhaar has already been used for KYC by another account' };
  }

  // Step 5: Cryptographic verification via @anon-aadhaar/core
  // This calls groth16.verify() with the circuit's verification key,
  // checking the full pairing equation over BN254.
  try {
    const isValid = await verify(pcd, useTestAadhaar);
    if (!isValid) {
      logger.warn(`Aadhaar ZK: Groth16 verification failed for user ${userId}`);
      return { valid: false, error: 'Proof verification failed — invalid ZK proof' };
    }
  } catch (err) {
    const message = err instanceof Error ? err.message : 'unknown error';
    logger.warn(`Aadhaar ZK: proof verification error for user ${userId}: ${message}`);
    // Public key mismatch throws (e.g. test proof against production key)
    return { valid: false, error: `Proof verification error: ${message}` };
  }

  logger.info(`Aadhaar ZK: proof verified successfully for user ${userId}`);
  return { valid: true, nullifierHash: nullifier, demographics: extractDemographics(pcd) };
}

// ---------------------------------------------------------------------------
// Internal validators
// ---------------------------------------------------------------------------

/**
 * Validate that the proof timestamp is recent.
 *
 * The timestamp from @anon-aadhaar/core is a Unix timestamp in seconds,
 * stored as a numeric string in `pcd.proof.timestamp`.
 */
function validateTimestamp(timestampStr: string): ZkVerificationResult {
  const proofTimeSec = Number(timestampStr);
  if (isNaN(proofTimeSec) || proofTimeSec <= 0) {
    return { valid: false, error: 'Invalid timestamp in proof' };
  }

  const nowSec = Math.floor(Date.now() / 1000);
  const ageSec = nowSec - proofTimeSec;

  if (ageSec > MAX_PROOF_AGE_S) {
    return {
      valid: false,
      error: `Proof is too old (${ageSec}s > ${MAX_PROOF_AGE_S}s limit)`,
    };
  }

  if (ageSec < -FUTURE_TOLERANCE_S) {
    return { valid: false, error: 'Proof timestamp is in the future' };
  }

  return { valid: true };
}

/**
 * Validate that the proof's signalHash matches the expected binding.
 *
 * The mobile app generates the proof with:
 *   signal = BigInt('0x' + userId.replace(/-/g, ''))
 *
 * The circuit hashes this into signalHash using keccak256 >> 8 (SNARK field).
 * We replicate the same computation using @anon-aadhaar/core's `hash()`.
 */
function validateSignalBinding(signalHash: string, userId: string): ZkVerificationResult {
  const expectedHash = computeExpectedSignalHash(userId);
  if (signalHash !== expectedHash) {
    return {
      valid: false,
      error: 'Signal does not match expected binding for this user',
    };
  }
  return { valid: true };
}

/**
 * Compute the expected signalHash for a given user ID.
 *
 * Converts the UUID to a 128-bit BigInt and hashes it using
 * @anon-aadhaar/core's `hash()` function (keccak256 >> 8,
 * SNARK-field compatible).
 *
 * The mobile app must use the same conversion:
 *   final signal = BigInt.parse(userId.replaceAll('-', ''), radix: 16);
 *   // Pass signal.toString() to generateArgs(..., signal: ...)
 */
export function computeExpectedSignalHash(userId: string): string {
  const signalBigInt = BigInt('0x' + userId.replace(/-/g, ''));
  return hash(signalBigInt);
}

// ---------------------------------------------------------------------------
// Demographic extraction
// ---------------------------------------------------------------------------

/**
 * Extract demographic information from the verified proof's claim.
 *
 * The claim is populated during proof generation on the mobile app,
 * with values already converted from raw circuit outputs to
 * human-readable form by @anon-aadhaar/core.
 */
function extractDemographics(pcd: Awaited<ReturnType<typeof deserialize>>): ZkVerificationResult['demographics'] {
  return {
    ageAbove18: pcd.claim.ageAbove18 ?? null,
    gender: pcd.claim.gender ?? null,
    state: pcd.claim.state ?? null,
    pincode: pcd.claim.pincode ?? null,
  };
}

// ---------------------------------------------------------------------------
// Exports for testing
// ---------------------------------------------------------------------------

export const _internal = {
  validateTimestamp,
  validateSignalBinding,
  extractDemographics,
  MAX_PROOF_AGE_S,
  FUTURE_TOLERANCE_S,
};
