/// Type-safe access to runtime environment variables loaded from `.env`.
///
/// Variables are read from the bundled `.env` asset via `flutter_dotenv`.
/// Every getter has a compiled fallback so the app works even when no `.env`
/// file is present (e.g. in CI or test environments).
///
/// Load order in [main]:
///   ```dart
///   await dotenv.load(fileName: '.env');
///   ```
library;

import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:aftermath/core/constants.dart';

/// Namespace for all environment-driven configuration values.
abstract final class Env {
  // -------------------------------------------------------------------------
  // Backend API
  // -------------------------------------------------------------------------

  /// Base URL of the AfterMath REST API (no trailing slash).
  /// Reads [API_BASE_URL] from `.env`; falls back to [kApiBaseUrl].
  static String get apiBaseUrl =>
      dotenv.maybeGet('API_BASE_URL') ?? kApiBaseUrl;

  /// Bearer token sent with every backend request.
  /// Reads [API_AUTH_TOKEN] from `.env`; empty string → no auth header sent.
  static String get apiAuthToken => dotenv.maybeGet('API_AUTH_TOKEN') ?? '';

  /// User ID used for onboarding verification calls.
  /// Reads [ONBOARDING_USER_ID] from `.env`; empty string means unset.
  static String get onboardingUserId =>
      dotenv.maybeGet('ONBOARDING_USER_ID') ?? '';

  // -------------------------------------------------------------------------
  // BLE Encryption
  // -------------------------------------------------------------------------

  /// Shared HMAC + XOR secret for BLE payload signing and encryption.
  /// Reads [BLE_ENCRYPTION_SECRET] from `.env`; falls back to dev placeholder.
  /// MUST be changed before deploying to production.
  static String get bleEncryptionSecret =>
      dotenv.maybeGet('BLE_ENCRYPTION_SECRET') ??
      'aftermath-dev-secret-replace-me';

  // -------------------------------------------------------------------------
  // Feature overrides (optional — compiled defaults used when absent)
  // -------------------------------------------------------------------------

  /// Seconds the user has to cancel before the SOS fires.
  /// Reads [SOS_CANCEL_COUNTDOWN_SEC] from `.env`; falls back to [kSosCancelCountdownSec].
  static int get sosCancelCountdownSec =>
      int.tryParse(dotenv.maybeGet('SOS_CANCEL_COUNTDOWN_SEC') ?? '') ??
      kSosCancelCountdownSec;

  /// Seconds after broadcast with no ACK before SMS fallback triggers.
  /// Reads [SMS_FALLBACK_TIMEOUT_SEC] from `.env`; falls back to [kSmsFallbackTimeout].
  static Duration get smsFallbackTimeout {
    final sec = int.tryParse(dotenv.maybeGet('SMS_FALLBACK_TIMEOUT_SEC') ?? '');
    return sec != null ? Duration(seconds: sec) : kSmsFallbackTimeout;
  }

  /// Maximum mesh relay hops (TTL).
  /// Reads [BLE_DEFAULT_TTL] from `.env`; falls back to [kDefaultTtl].
  static int get bleDefaultTtl =>
      int.tryParse(dotenv.maybeGet('BLE_DEFAULT_TTL') ?? '') ?? kDefaultTtl;
}
