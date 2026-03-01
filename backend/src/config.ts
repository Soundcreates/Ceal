/**
 * CEAL Backend — Environment configuration.
 *
 * Validates all required env vars at startup via Zod.
 */

import 'dotenv/config';
import { z } from 'zod';

const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'production', 'test']).default('development'),
  PORT: z.coerce.number().int().positive().default(3000),
  HOST: z.string().default('0.0.0.0'),
  CORS_ORIGIN: z.string().default('http://localhost:3001'),

  // Database
  DATABASE_URL: z.string().url().startsWith('postgresql'),

  // BLE encryption secret (hex, 64 chars = 32 bytes)
  BLE_ENCRYPTION_SECRET: z.string().min(16),

  // Server secret for deterministic BLE UID generation
  SERVER_SECRET: z.string().min(16).default('ceal-default-server-secret-change-me'),

  // Twilio
  TWILIO_ACCOUNT_SID: z.string().startsWith('AC'),
  TWILIO_AUTH_TOKEN: z.string().min(1),
  TWILIO_API_KEY_SID: z.string().startsWith('SK').optional(),
  TWILIO_API_KEY_SECRET: z.string().optional(),
  TWILIO_FROM_NUMBER: z.string().startsWith('+'),
  TWILIO_ESCALATION_NUMBER: z.string().startsWith('+'),

  // JWT
  JWT_SECRET: z.string().min(32),
  JWT_EXPIRES_IN: z.string().default('1h'),

  // Rate limiting
  RATE_LIMIT_MAX: z.coerce.number().int().positive().default(100),
  RATE_LIMIT_WINDOW_MS: z.coerce.number().int().positive().default(60_000),

  // Logging
  LOG_LEVEL: z.enum(['error', 'warn', 'info', 'http', 'debug']).default('info'),

  // Aadhaar ZK verification (Anon Aadhaar)
  // Set to 'true' to verify against the test UIDAI public key hash
  // (for development/staging). Defaults to 'false' (production keys).
  USE_TEST_AADHAAR: z.enum(['true', 'false']).default('false'),

  // Gemini (disaster image verification)
  GEMINI_API_KEY: z.string().min(1).optional(),

  // Cloudinary (disaster image hosting)
  CLOUDINARY_CLOUD_NAME: z.string().min(1).optional(),
  CLOUDINARY_API_KEY: z.string().min(1).optional(),
  CLOUDINARY_API_SECRET: z.string().min(1).optional(),

  // Disaster reporting
  DISASTER_REPORT_RATE_LIMIT: z.coerce.number().int().positive().default(5),
  DISASTER_IMAGE_MAX_BYTES: z.coerce.number().int().positive().default(5_242_880), // 5 MB
});

export type Env = z.infer<typeof envSchema>;

function loadEnv(): Env {
  const result = envSchema.safeParse(process.env);
  if (!result.success) {
    // Filter out Twilio API Key errors if Account SID and Auth Token are present
    const issues = result.error.issues.filter(issue => {
      if (issue.path[0] === 'TWILIO_API_KEY_SID' || issue.path[0] === 'TWILIO_API_KEY_SECRET') {
        // Ignore missing API Key if Account SID and Auth Token are present
        return !(process.env.TWILIO_ACCOUNT_SID && process.env.TWILIO_AUTH_TOKEN);
      }
      return true;
    });
    if (issues.length > 0) {
      console.error('Invalid environment variables:');
      for (const issue of issues) {
        console.error(`   ${issue.path.join('.')}: ${issue.message}`);
      }
      process.exit(1);
    }
  }
  return result.data!;
}

export const env = loadEnv();
