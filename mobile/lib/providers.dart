/// Global Riverpod providers for AfterMath services.
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import 'package:aftermath/core/constants.dart';
import 'package:aftermath/core/encryption.dart';
import 'package:aftermath/core/env.dart';
import 'package:aftermath/core/permissions.dart';
import 'package:aftermath/services/backend_service.dart';
import 'package:aftermath/services/background_relay_service.dart';
import 'package:aftermath/services/ble_advertiser_service.dart';
import 'package:aftermath/services/ble_scanner_service.dart';
import 'package:aftermath/services/connectivity_worker.dart';
import 'package:aftermath/services/foreground_service.dart';
import 'package:aftermath/services/location_service.dart';
import 'package:aftermath/services/mesh_relay_service.dart';
import 'package:aftermath/services/packet_reassembler.dart';
import 'package:aftermath/services/pending_events_db.dart';
import 'package:aftermath/services/queue_service.dart';
import 'package:aftermath/services/settings_service.dart';
import 'package:aftermath/services/sms_fallback_service.dart';
import 'package:aftermath/services/sos_notification_service.dart';

// ---------------------------------------------------------------------------
// Singleton service providers
// ---------------------------------------------------------------------------

final permissionServiceProvider = Provider<PermissionService>((ref) {
  return PermissionService();
});

final encryptionServiceProvider = Provider<EncryptionService>((ref) {
  return EncryptionService(secret: Env.bleEncryptionSecret);
});

final locationServiceProvider = Provider<LocationService>((ref) {
  return LocationService();
});

final queueServiceProvider = Provider<QueueService>((ref) {
  final svc = QueueService();
  ref.onDispose(() => svc.dispose());
  return svc;
});

final backendServiceProvider = Provider<BackendService>((ref) {
  final svc = BackendService(baseUrl: Env.apiBaseUrl);
  if (Env.apiAuthToken.isNotEmpty) svc.authToken = Env.apiAuthToken;
  ref.onDispose(() => svc.dispose());
  return svc;
});

final bleAdvertiserProvider = Provider<BleAdvertiserService>((ref) {
  final svc = BleAdvertiserService();
  ref.onDispose(() => svc.dispose());
  return svc;
});

final bleScannerProvider = Provider<BleScannerService>((ref) {
  final svc = BleScannerService();
  ref.onDispose(() => svc.dispose());
  return svc;
});

final packetReassemblerProvider = Provider<PacketReassembler>((ref) {
  final reassembler = PacketReassembler();
  ref.onDispose(() => reassembler.dispose());
  return reassembler;
});

final meshRelayProvider = Provider<MeshRelayService>((ref) {
  final svc = MeshRelayService(
    advertiser: ref.watch(bleAdvertiserProvider),
    backendService: ref.watch(backendServiceProvider),
    queueService: ref.watch(queueServiceProvider),
    locationService: ref.watch(locationServiceProvider),
  );
  ref.onDispose(() => svc.dispose());
  return svc;
});

final foregroundServiceProvider = Provider<ForegroundService>((ref) {
  return ForegroundService();
});

final settingsServiceProvider = Provider<SettingsService>((ref) {
  final svc = SettingsService();
  ref.onDispose(() => svc.dispose());
  return svc;
});

final smsFallbackProvider = Provider<SmsFallbackService>((ref) {
  return SmsFallbackService();
});

// ---------------------------------------------------------------------------
// Always-on SOS relay services
// ---------------------------------------------------------------------------

/// Persistent pending-events database for offline-first queue.
final pendingEventsDbProvider = Provider<PendingEventsDb>((ref) {
  final db = PendingEventsDb();
  ref.onDispose(() => db.dispose());
  return db;
});

/// SOS local notification service.
final sosNotificationServiceProvider = Provider<SosNotificationService>((ref) {
  return SosNotificationService();
});

/// Connectivity worker — drains pending queue when network is available.
final connectivityWorkerProvider = Provider<ConnectivityWorker>((ref) {
  final worker = ConnectivityWorker(
    pendingDb: ref.watch(pendingEventsDbProvider),
    backendService: ref.watch(backendServiceProvider),
  );
  ref.onDispose(() => worker.dispose());
  return worker;
});

/// Background relay service — the always-on BLE SOS detection + escalation engine.
final backgroundRelayProvider = Provider<BackgroundRelayService>((ref) {
  final svc = BackgroundRelayService(
    scanner: ref.watch(bleScannerProvider),
    advertiser: ref.watch(bleAdvertiserProvider),
    locationService: ref.watch(locationServiceProvider),
    pendingDb: ref.watch(pendingEventsDbProvider),
    connectivityWorker: ref.watch(connectivityWorkerProvider),
    backendService: ref.watch(backendServiceProvider),
    smsService: ref.watch(smsFallbackProvider),
    notificationService: ref.watch(sosNotificationServiceProvider),
  );
  ref.onDispose(() => svc.dispose());
  return svc;
});

/// Persistent device UUID stored in secure storage.
final deviceUuidProvider = FutureProvider<String>((ref) async {
  const storage = FlutterSecureStorage();
  const key = 'aftermath_device_uuid';
  var uuid = await storage.read(key: key);
  if (uuid == null) {
    uuid = const Uuid().v4();
    await storage.write(key: key, value: uuid);
  }
  return uuid;
});

/// Persistent 6-byte BLE UID stored in secure storage.
///
/// Generated once per install — a pseudonymous static identifier used in
/// CORE V2 packets. NOT derived from device ID; fully random.
final bleUidProvider = FutureProvider<Uint8List>((ref) async {
  const storage = FlutterSecureStorage();
  const key = 'aftermath_ble_uid';
  final stored = await storage.read(key: key);
  if (stored != null && stored.length == kBleUidSize * 2) {
    // Stored as hex string — decode back to bytes.
    final bytes = Uint8List(kBleUidSize);
    for (int i = 0; i < kBleUidSize; i++) {
      bytes[i] = int.parse(stored.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }
  // Generate random 6-byte UID.
  final rng = Random.secure();
  final uid = Uint8List(kBleUidSize);
  for (int i = 0; i < kBleUidSize; i++) {
    uid[i] = rng.nextInt(256);
  }
  final hex = uid.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  await storage.write(key: key, value: hex);
  return uid;
});

/// Live BLE scan results — consumed by the broadcasting view to show nearby devices.
///
/// IMPORTANT: FlutterBluePlus.scanResults emits on every advertisement packet,
/// which can fire at 30-100 Hz during active scanning. Watching it directly from
/// a widget triggers rebuilds faster than the GPU surface can consume frames,
/// causing BLASTBufferQueue exhaustion (a:7 max:5+2). We therefore cache the
/// latest result and re-emit at a fixed 1 Hz, keeping rebuilds well within
/// the display's vsync budget.
final nearbyDevicesStreamProvider = StreamProvider.autoDispose<List<ScanResult>>((ref) {
  var latest = <ScanResult>[];
  final sub = FlutterBluePlus.scanResults.listen((results) => latest = results);
  ref.onDispose(sub.cancel);
  // Poll the cached value once per second — smooth UI without frame flooding.
  return Stream.periodic(const Duration(seconds: 1), (_) => latest);
});
