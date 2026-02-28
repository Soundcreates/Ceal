/// Background relay orchestrator — the always-on SOS detection + escalation
/// engine that runs inside the foreground service.
///
/// Responsibilities:
///  1. Continuous BLE scanning with periodic restart to avoid OS throttling.
///  2. Validate + deduplicate incoming packets via in-memory LRU cache.
///  3. Enqueue new SOS events in the persistent [PendingEventsDb].
///  4. Show high-priority notification to the user.
///  5. Attempt immediate SMS (Android) if auto-SMS is enabled.
///  6. Kick the [ConnectivityWorker] to upload when network is available.
///  7. Re-broadcast via BLE mesh.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:aftermath/core/poc_config.dart';
import 'package:aftermath/models/core_sos_packet.dart';
import 'package:aftermath/models/responder.dart';
import 'package:aftermath/models/sos_event.dart';
import 'package:aftermath/services/ble_scanner_service.dart';
import 'package:aftermath/services/ble_advertiser_service.dart';
import 'package:aftermath/services/connectivity_worker.dart';
import 'package:aftermath/services/location_service.dart';
import 'package:aftermath/services/pending_events_db.dart';
import 'package:aftermath/services/sms_fallback_service.dart';
import 'package:aftermath/services/sos_notification_service.dart';
import 'package:aftermath/features/alerts/alerts_notifier.dart';

/// In-memory LRU dedup entry.
class _DedupEntry {
  _DedupEntry(this.key, this.expiresAt);
  final String key;
  final DateTime expiresAt;
  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

class BackgroundRelayService {
  BackgroundRelayService({
    required this.scanner,
    required this.advertiser,
    required this.locationService,
    required this.pendingDb,
    required this.connectivityWorker,
    required this.smsService,
    required this.notificationService,
    this.alertsNotifier,
  });

  final BleScannerService scanner;
  final BleAdvertiserService advertiser;
  final LocationService locationService;
  final PendingEventsDb pendingDb;
  final ConnectivityWorker connectivityWorker;
  final SmsFallbackService smsService;
  final SosNotificationService notificationService;
  AlertsNotifier? alertsNotifier;

  Timer? _scanRestartTimer;
  bool _running = false;

  /// In-memory LRU dedup cache: key → expiry.
  final LinkedHashMap<String, _DedupEntry> _dedupCache = LinkedHashMap();

  // ---------------------------------------------------------------------------
  // Start / Stop
  // ---------------------------------------------------------------------------

  Future<void> start() async {
    if (_running) return;
    _running = true;

    // Wire up scanner callback.
    scanner.onCorePacketReceived = _onCorePacket;

    // Start BLE scanning.
    await scanner.startScanning();

    // Periodic BLE scan restart to avoid Android throttling.
    _scanRestartTimer = Timer.periodic(kBleScanRestartInterval, (_) async {
      debugPrint('[BackgroundRelay] Restarting BLE scan to avoid throttle.');
      await scanner.stopScanning();
      await Future<void>.delayed(const Duration(seconds: 2));
      if (_running) await scanner.startScanning();
    });

    // Start connectivity worker.
    connectivityWorker.start();

    // Init notification service.
    await notificationService.init();

    debugPrint('[BackgroundRelay] Started — always-on scanning active.');
  }

  Future<void> stop() async {
    _running = false;
    _scanRestartTimer?.cancel();
    _scanRestartTimer = null;
    await scanner.stopScanning();
    connectivityWorker.stop();
    debugPrint('[BackgroundRelay] Stopped.');
  }

  // ---------------------------------------------------------------------------
  // Packet handler
  // ---------------------------------------------------------------------------

  void _onCorePacket(CoreSosPacket packet, String deviceId, int rssi) {
    final dedupKey = '${packet.bleUidHex}:${packet.sequence}';

    // Check dedup cache.
    if (_isDuplicate(dedupKey)) {
      return;
    }
    _addToDedup(dedupKey);

    debugPrint('[BackgroundRelay] New SOS: uid=${packet.bleUidHex} seq=${packet.sequence} rssi=$rssi');

    // Fire-and-forget the async pipeline.
    _handleNewSos(packet, deviceId, rssi);
  }

  Future<void> _handleNewSos(
      CoreSosPacket packet, String deviceId, int rssi) async {
    // 1. Get location.
    final pos = await locationService.getCurrentPosition();
    final lat = pos?.latitude ?? 0.0;
    final lon = pos?.longitude ?? 0.0;

    // 2. Build pending event.
    final eventId = 'uid:${packet.bleUidHex}:${packet.sequence}';
    final pe = PendingEvent(
      id: eventId,
      uid: packet.bleUidHex,
      flags: packet.flags,
      sequence: packet.sequence,
      receiverLat: lat,
      receiverLon: lon,
      rssi: rssi,
      timestamp: DateTime.now().toUtc().millisecondsSinceEpoch,
    );

    // 3. Persist to local queue.
    await pendingDb.insert(pe);

    // 4. Build SosEvent for UI / backend / mesh relay.
    final sosEvent = SosEvent(
      id: eventId,
      bleUid: Uint8List.fromList(packet.bleUid),
      flags: packet.flags,
      sequence: packet.sequence,
      timestamp: DateTime.now().toUtc(),
      receiverLocation:
          pos != null ? ReceiverLocation(lat: lat, lon: lon, accuracy: pos.accuracy) : null,
      rssi: rssi,
    );

    // 5. Push to UI alert list.
    alertsNotifier?.addAlert(sosEvent);

    // 6. Show high-priority notification.
    double? distance;
    if (pos != null) {
      // Rough estimate — we don't know sender's location, so skip distance.
      // Future: use RSSI-based distance estimation.
    }
    await notificationService.showSosDetected(pe, distanceMetres: distance);

    // 7. Attempt immediate SMS (Android).
    if (kAutoSmsEnabled && Platform.isAndroid) {
      await _sendSmsSafe(pe);
    }

    // 8. Try immediate backend upload.
    final hasNet = await connectivityWorker.hasConnectivity();
    if (hasNet) {
      unawaited(connectivityWorker.drainQueue());
    }

    // 9. Re-broadcast via BLE mesh.
    _rebroadcast(packet);
  }

  // ---------------------------------------------------------------------------
  // SMS
  // ---------------------------------------------------------------------------

  Future<void> _sendSmsSafe(PendingEvent pe) async {
    for (int attempt = 0; attempt < kSmsMaxRetries; attempt++) {
      try {
        final targets = kSmsDemoNumber
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();

        bool anySent = false;
        for (final number in targets) {
          // Build a proper EmergencyContact and send.
          smsService.emergencyContacts = [
            EmergencyContact(name: 'SOS Alert', phone: number),
          ];
          smsService.enabled = true;

          final event = SosEvent(
            id: pe.id,
            bleUid: Uint8List(6),
            flags: pe.flags,
            sequence: pe.sequence,
            timestamp:
                DateTime.fromMillisecondsSinceEpoch(pe.timestamp, isUtc: true),
            receiverLocation:
                ReceiverLocation(lat: pe.receiverLat, lon: pe.receiverLon),
          );

          final sent = await smsService.sendSos(event);
          if (sent > 0) anySent = true;
        }

        if (anySent) {
          await pendingDb.markSmsSent(pe.id);
          debugPrint('[BackgroundRelay] SMS sent for ${pe.id}');
          return;
        }
      } catch (e) {
        debugPrint('[BackgroundRelay] SMS attempt ${attempt + 1} failed: $e');
      }

      // Exponential backoff.
      if (attempt < kSmsMaxRetries - 1) {
        await Future<void>.delayed(kSmsRetryBackoff * (attempt + 1));
      }
    }

    debugPrint('[BackgroundRelay] SMS failed after $kSmsMaxRetries attempts for ${pe.id}');
  }

  // ---------------------------------------------------------------------------
  // BLE re-broadcast
  // ---------------------------------------------------------------------------

  void _rebroadcast(CoreSosPacket packet) {
    try {
      advertiser.broadcastCoreSos(packet);
    } catch (e) {
      debugPrint('[BackgroundRelay] Rebroadcast error: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Dedup LRU
  // ---------------------------------------------------------------------------

  bool _isDuplicate(String key) {
    _purgeExpiredDedup();
    final entry = _dedupCache[key];
    return entry != null && !entry.isExpired;
  }

  void _addToDedup(String key) {
    _dedupCache[key] = _DedupEntry(
      key,
      DateTime.now().add(kDedupCacheTtl),
    );

    // Evict oldest if over capacity.
    while (_dedupCache.length > kDedupCacheMaxSize) {
      _dedupCache.remove(_dedupCache.keys.first);
    }
  }

  void _purgeExpiredDedup() {
    _dedupCache.removeWhere((_, entry) => entry.isExpired);
  }

  // ---------------------------------------------------------------------------
  // Dispose
  // ---------------------------------------------------------------------------

  Future<void> dispose() async {
    await stop();
    _dedupCache.clear();
  }
}
