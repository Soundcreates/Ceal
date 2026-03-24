/**
 * CEAL Backend — Aadhaar Zero-Knowledge Verification Service.
 */

import { createRequire } from 'node:module';
import { logger } from '../logger.js';
import type { UserRepository } from '../db/user-repository.js';

const require = createRequire(import.meta.url);
const anonAadhaarCore = require('@anon-aadhaar/core') as AadhaarCoreModule;

const MAX_PROOF_AGE_S = 15 * 60;
const FUTURE_TOLERANCE_S = 60;

export interface ZkVerificationResult {
  valid: boolean;
  error?: string;
  nullifierHash?: string;
  demographics?: {
    ageAbove18: boolean | null;
    gender: string | null;
    state: string | null;
    pincode: string | null;
  };
}

interface InitArgs {
  wasmURL: string;
  zkeyURL: string;
  vkeyURL: string;
  artifactsOrigin?: string;
}

interface AnonAadhaarPcd {
  proof: {
    timestamp: string;
    signalHash: string;
    nullifier: string;
  };
  claim: {
    ageAbove18?: boolean | null;
    gender?: string | null;
    state?: string | null;
    pincode?: string | null;
  };
}

interface AadhaarCoreModule {
  init: (args: InitArgs) => Promise<void>;
  verify: (pcd: AnonAadhaarPcd, useTestAadhaar?: boolean) => Promise<boolean>;
  deserialize: (serialized: string) => Promise<AnonAadhaarPcd>;
  hash: (signal: bigint) => string;
  artifactUrls: {
    v2: { wasm: string; zkey: string; vk: string };
  };
  ArtifactsOrigin: {
    server: string;
  };
}

let initialized = false;

export async function initAnonAadhaar(): Promise<void> {
  if (initialized) return;

  const initArgs: InitArgs = {
    wasmURL: anonAadhaarCore.artifactUrls.v2.wasm,
    zkeyURL: anonAadhaarCore.artifactUrls.v2.zkey,
    vkeyURL: anonAadhaarCore.artifactUrls.v2.vk,
    artifactsOrigin: anonAadhaarCore.ArtifactsOrigin.server,
  };

  await anonAadhaarCore.init(initArgs);
  initialized = true;
  logger.info('Anon Aadhaar core initialized');
}

export function _resetInit(): void {
  initialized = false;
}

export async function verifyAadhaarProof(
  userId: string,
  serializedProof: string,
  useTestAadhaar: boolean,
  userRepo: UserRepository,
): Promise<ZkVerificationResult> {
  await initAnonAadhaar();

  let pcd: AnonAadhaarPcd;
  try {
    pcd = await anonAadhaarCore.deserialize(serializedProof);
  } catch (err) {
    const msg = err instanceof Error ? err.message : 'unknown error';
    logger.warn(`Aadhaar ZK: failed to deserialize proof for user ${userId}: ${msg}`);
    return { valid: false, error: 'Failed to deserialize proof - invalid format' };
  }

  const timestampCheck = validateTimestamp(pcd.proof.timestamp);
  if (!timestampCheck.valid) {
    logger.warn(`Aadhaar ZK: timestamp invalid for user ${userId}: ${timestampCheck.error}`);
    return timestampCheck;
  }

  const signalCheck = validateSignalBinding(pcd.proof.signalHash, userId);
  if (!signalCheck.valid) {
    logger.warn(`Aadhaar ZK: signal binding failed for user ${userId}: ${signalCheck.error}`);
    return signalCheck;
  }

  const nullifier = pcd.proof.nullifier;
  const existingUser = await userRepo.findByNullifier(nullifier);
  if (existingUser) {
    if (existingUser.id === userId) {
      logger.info(`Aadhaar ZK: user ${userId} already verified with this nullifier`);
      return { valid: true, nullifierHash: nullifier, demographics: extractDemographics(pcd) };
    }
    logger.warn(`Aadhaar ZK: nullifier collision - user ${userId} tried nullifier owned by ${existingUser.id}`);
    return { valid: false, error: 'This Aadhaar has already been used for KYC by another account' };
  }

  try {
    const isValid = await anonAadhaarCore.verify(pcd, useTestAadhaar);
    if (!isValid) {
      logger.warn(`Aadhaar ZK: Groth16 verification failed for user ${userId}`);
      return { valid: false, error: 'Proof verification failed - invalid ZK proof' };
    }
  } catch (err) {
    const message = err instanceof Error ? err.message : 'unknown error';
    logger.warn(`Aadhaar ZK: proof verification error for user ${userId}: ${message}`);
    return { valid: false, error: `Proof verification error: ${message}` };
  }

  logger.info(`Aadhaar ZK: proof verified successfully for user ${userId}`);
  return { valid: true, nullifierHash: nullifier, demographics: extractDemographics(pcd) };
}

function validateTimestamp(timestampStr: string): ZkVerificationResult {
  const proofTimeSec = Number(timestampStr);
  if (Number.isNaN(proofTimeSec) || proofTimeSec <= 0) {
    return { valid: false, error: 'Invalid timestamp in proof' };
  }

  const nowSec = Math.floor(Date.now() / 1000);
  const ageSec = nowSec - proofTimeSec;
  if (ageSec > MAX_PROOF_AGE_S) {
    return { valid: false, error: `Proof is too old (${ageSec}s > ${MAX_PROOF_AGE_S}s limit)` };
  }
  if (ageSec < -FUTURE_TOLERANCE_S) {
    return { valid: false, error: 'Proof timestamp is in the future' };
  }

  return { valid: true };
}

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

export function computeExpectedSignalHash(userId: string): string {
  const signalBigInt = BigInt(`0x${userId.replace(/-/g, '')}`);
  return anonAadhaarCore.hash(signalBigInt);
}

function extractDemographics(pcd: AnonAadhaarPcd): ZkVerificationResult['demographics'] {
  return {
    ageAbove18: pcd.claim.ageAbove18 ?? null,
    gender: pcd.claim.gender ?? null,
    state: pcd.claim.state ?? null,
    pincode: pcd.claim.pincode ?? null,
  };
}

export const _internal = {
  validateTimestamp,
  validateSignalBinding,
  extractDemographics,
  MAX_PROOF_AGE_S,
  FUTURE_TOLERANCE_S,
};
