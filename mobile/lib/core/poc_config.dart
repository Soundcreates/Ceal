/// Always-on configuration for AfterMath BLE SOS relay + auto-escalation.
///
/// The app always runs continuously in background, scans BLE 24/7, queues
/// SOS events locally, auto-uploads when connected, and sends SMS on detection.
library;

import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Auto-SMS: device sends SMS immediately on SOS detection (Android only).
const bool kAutoSmsEnabled = true;

/// SMS target number(s) — override via SMS_DEMO_NUMBER in .env.
/// Used only as a last-resort fallback when no victim profile is available.
final String kSmsDemoNumber =
    dotenv.maybeGet('SMS_DEMO_NUMBER') ?? '+91XXXXXXXXXX';

/// Escalation operator number — always receives a direct device SMS copy
/// in addition to the backend Twilio message.
/// Override via ESCALATION_PHONE in .env.
final String kEscalationPhone = dotenv.maybeGet('ESCALATION_PHONE') ?? '';

/// Interval between queue drain attempts when connectivity is available.
const Duration kQueueDrainInterval = Duration(seconds: 5);

/// BLE scan restart interval to avoid OS throttling.
const Duration kBleScanRestartInterval = Duration(minutes: 20);

/// Maximum entries in the in-memory dedup LRU cache.
const int kDedupCacheMaxSize = 512;

/// How long dedup entries stay valid.
const Duration kDedupCacheTtl = Duration(minutes: 5);

/// Retry backoff base for failed SMS sends.
const Duration kSmsRetryBackoff = Duration(seconds: 10);

/// Maximum SMS retry attempts per event.
const int kSmsMaxRetries = 3;
