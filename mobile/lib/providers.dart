/// Global Riverpod providers for AfterMath services.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aftermath/core/encryption.dart';
import 'package:aftermath/core/permissions.dart';
import 'package:aftermath/services/backend_service.dart';
import 'package:aftermath/services/ble_advertiser_service.dart';
import 'package:aftermath/services/ble_scanner_service.dart';
import 'package:aftermath/services/foreground_service.dart';
import 'package:aftermath/services/location_service.dart';
import 'package:aftermath/services/mesh_relay_service.dart';
import 'package:aftermath/services/packet_reassembler.dart';
import 'package:aftermath/services/queue_service.dart';
import 'package:aftermath/services/sms_fallback_service.dart';

// ---------------------------------------------------------------------------
// Singleton service providers
// ---------------------------------------------------------------------------

final permissionServiceProvider = Provider<PermissionService>((ref) {
  return PermissionService();
});

final encryptionServiceProvider = Provider<EncryptionService>((ref) {
  return EncryptionService();
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
  final svc = BackendService();
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
  );
  ref.onDispose(() => svc.dispose());
  return svc;
});

final foregroundServiceProvider = Provider<ForegroundService>((ref) {
  return ForegroundService();
});

final smsFallbackProvider = Provider<SmsFallbackService>((ref) {
  return SmsFallbackService();
});
