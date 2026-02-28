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
      debugPrint(
        '[BackgroundRelay] DEDUP HIT — uid=${packet.bleUidHex} seq=${packet.sequence} '
        'rssi=$rssi | cacheSize=${_dedupCache.length}',
      );
      return;
    }
    _addToDedup(dedupKey);

    debugPrint(
      '[BackgroundRelay] NEW SOS packet | uid=${packet.bleUidHex} seq=${packet.sequence} '
      'rssi=$rssi flags=0x${packet.flags.toRadixString(16).padLeft(2, '0')} '
      'deviceId=$deviceId | cacheSize=${_dedupCache.length}',
    );

    // Fire-and-forget the async pipeline.
    _handleNewSos(packet, deviceId, rssi);
  }

  Future<void> _handleNewSos(
      CoreSosPacket packet, String deviceId, int rssi) async {
    // 1. Get location.
    final pos = await locationService.getCurrentPosition();
    final lat = pos?.latitude ?? 0.0;
    final lon = pos?.longitude ?? 0.0;
    debugPrint(
      '[BackgroundRelay] Location for uid=${packet.bleUidHex}: '
      'lat=$lat lon=$lon acc=${pos != null ? pos.accuracy.toStringAsFixed(1) : 'unknown'}m',
    );

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
    final queueDepth = await pendingDb.pendingCount();
    debugPrint(
      '[BackgroundRelay] Persisted ${pe.id} | queueDepth=$queueDepth',
    );

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
      debugPrint('[BackgroundRelay] Attempting SMS fallback for ${pe.id}');
      await _sendSmsSafe(pe);
    }

    // 8. Try immediate backend upload.
    final hasNet = await connectivityWorker.hasConnectivity();
    debugPrint('[BackgroundRelay] Connectivity check for ${pe.id}: hasNet=$hasNet');
    if (hasNet) {
      debugPrint('[BackgroundRelay] Draining queue ($queueDepth pending)');
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
        debugPrint(
          '[BackgroundRelay] SMS attempt ${attempt + 1}/$kSmsMaxRetries | '
          'id=${pe.id} targets=[${targets.join(', ')}]',
        );

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
          debugPrint(
            '[BackgroundRelay] SMS to $number: sent=${sent > 0} (count=$sent)',
          );
          if (sent > 0) anySent = true;
        }

        if (anySent) {
          await pendingDb.markSmsSent(pe.id);
          debugPrint('[BackgroundRelay] SMS sent OK for ${pe.id} after attempt ${attempt + 1}');
          return;
        }
      } catch (e) {
        debugPrint('[BackgroundRelay] SMS attempt ${attempt + 1} threw: $e');
      }

      // Exponential backoff.
      if (attempt < kSmsMaxRetries - 1) {
        final delay = kSmsRetryBackoff * (attempt + 1);
        debugPrint('[BackgroundRelay] SMS retry backoff: ${delay.inSeconds}s');
        await Future<void>.delayed(delay);
      }
    }

    debugPrint('[BackgroundRelay] SMS FAILED all $kSmsMaxRetries attempts for ${pe.id}');
  }

  // ---------------------------------------------------------------------------
  // BLE re-broadcast
  // ---------------------------------------------------------------------------

  void _rebroadcast(CoreSosPacket packet) {
    debugPrint(
      '[BackgroundRelay] Rebroadcasting via BLE | uid=${packet.bleUidHex} seq=${packet.sequence}',
    );
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
