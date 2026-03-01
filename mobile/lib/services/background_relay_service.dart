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
import 'package:aftermath/services/backend_service.dart';
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
    required this.backendService,
    required this.smsService,
    required this.notificationService,
    this.alertsNotifier,
  });

  final BleScannerService scanner;
  final BleAdvertiserService advertiser;
  final LocationService locationService;
  final PendingEventsDb pendingDb;
  final ConnectivityWorker connectivityWorker;
  final BackendService backendService;
  final SmsFallbackService smsService;
  final SosNotificationService notificationService;
  AlertsNotifier? alertsNotifier;

  /// This device's own BLE UID (hex) — set at startup so the scanner
  /// ignores packets originated by this device (self-loop prevention).
  String? ownBleUidHex;

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
    // Self-loop guard — ignore our own BLE advertisements picked up by
    // our own scanner. Without this the victim device wastes resources
    // trying to relay its own SOS.
    if (ownBleUidHex != null && packet.bleUidHex == ownBleUidHex) {
      return; // silently skip — no log spam
    }

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

    // TTL guard — drop packets that have exhausted their hop budget.
    if (packet.ttl <= 0) {
      debugPrint(
        '[BackgroundRelay] TTL EXPIRED — uid=${packet.bleUidHex} seq=${packet.sequence} '
        'ttl=${packet.ttl} | dropping',
      );
      return;
    }

    debugPrint(
      '[BackgroundRelay] *** NEW SOS DETECTED *** | uid=${packet.bleUidHex} '
      'seq=${packet.sequence} rssi=$rssi ttl=${packet.ttl} hops=${packet.relayHops} '
      'flags=0x${packet.flags.toRadixString(16).padLeft(2, '0')} '
      'deviceId=$deviceId | cacheSize=${_dedupCache.length}',
    );

    // Fire-and-forget the async pipeline (with top-level safety net).
    _handleNewSos(packet, deviceId, rssi);
  }

  Future<void> _handleNewSos(
      CoreSosPacket packet, String deviceId, int rssi) async {
   try {
    final bleUid = packet.bleUidHex;

    // 1. Get location.
    final pos = await locationService.getCurrentPosition();
    final lat = pos?.latitude ?? 0.0;
    final lon = pos?.longitude ?? 0.0;
    debugPrint(
      '[BackgroundRelay] Location for uid=$bleUid: '
      'lat=$lat lon=$lon acc=${pos != null ? pos.accuracy.toStringAsFixed(1) : 'unknown'}m',
    );

    // 2. Build pending event.
    final eventId = 'uid:$bleUid:${packet.sequence}';
    final hops = packet.relayHops;
    final pe = PendingEvent(
      id: eventId,
      uid: bleUid,
      flags: packet.flags,
      sequence: packet.sequence,
      receiverLat: lat,
      receiverLon: lon,
      rssi: rssi,
      timestamp: DateTime.now().toUtc().millisecondsSinceEpoch,
      relayHops: hops,
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
      relayHops: hops,
      receiverLocation:
          pos != null ? ReceiverLocation(lat: lat, lon: lon, accuracy: pos.accuracy) : null,
      rssi: rssi,
    );

    // 5. Push to UI alert list.
    alertsNotifier?.addAlert(sosEvent);

    // 6. Look up victim profile from backend DB via BLE UID.
    //    Uses whatever connectivity is available (mobile data / WiFi) — no waiting.
    VictimProfile? victimProfile;
    try {
      debugPrint('[BackgroundRelay] Looking up victim profile for uid=$bleUid');
      victimProfile = await backendService.lookupVictimProfile(bleUid);
      if (victimProfile != null) {
        debugPrint(
          '[BackgroundRelay] Victim resolved: '
          'name=${victimProfile.name} phone=${victimProfile.phone} '
          'contacts=${victimProfile.contacts.length} '
          'blood=${victimProfile.medical?.bloodGroup ?? 'unknown'}',
        );
      } else {
        debugPrint('[BackgroundRelay] No registered victim for uid=$bleUid');
      }
    } catch (e) {
      debugPrint('[BackgroundRelay] Victim profile lookup failed: $e');
    }

    // 7. Show high-priority notification enriched with victim info.
    await notificationService.showSosDetected(
      pe,
      victimProfile: victimProfile,
      rssi: rssi,
    );

    // 8. IMMEDIATELY ingest to backend (triggers Twilio SMS to contacts).
    //    Do NOT gate on connectivity — attempt now with whatever network is
    //    available. If it fails, the event is already in the local queue and
    //    ConnectivityWorker will retry when network returns.
    debugPrint('[BackgroundRelay] Immediately ingesting ${pe.id} to backend');
    try {
      final ok = await backendService.ingestSos(sosEvent);
      if (ok) {
        await pendingDb.markSentToBackend(pe.id);
        debugPrint('[BackgroundRelay] Backend ingest OK for ${pe.id}');
      } else {
        debugPrint('[BackgroundRelay] Backend ingest returned non-2xx for ${pe.id}');
      }
    } catch (e) {
      debugPrint('[BackgroundRelay] Backend ingest failed (will retry): $e');
    }

    // 9. Send SMS directly from device (Android) to victim's emergency contacts
    //    + escalation operator.  The relayer's phone acts as a modem — no user
    //    confirmation, always automatic.  The victim's real-time GPS location
    //    (captured in step 1) is embedded in every message.
    if (Platform.isAndroid) {
      debugPrint('[BackgroundRelay] Sending device SMS for ${pe.id}');
      await _sendSmsSafe(pe, victimProfile: victimProfile);
    }

    // 10. Drain any other pending events in the queue.
    unawaited(connectivityWorker.drainQueue());

    // 11. Re-broadcast via BLE mesh (with decremented TTL).
    _rebroadcast(packet);
   } catch (e, st) {
    debugPrint(
      '[BackgroundRelay] *** _handleNewSos FAILED *** | '
      'uid=${packet.bleUidHex} seq=${packet.sequence} | error: $e\n$st',
    );
   }
  }

  // ---------------------------------------------------------------------------
  // Device SMS (relayer as modem)
  // ---------------------------------------------------------------------------

  /// Sends SMS directly from the relayer's device to:
  ///   1. Every emergency contact registered in the victim's profile.
  ///   2. The configured escalation operator number.
  ///   3. Falls back to [kSmsDemoNumber] only if no profile is available.
  ///
  /// The relayer's real-time GPS position (already in [pe.receiverLat/Lon])
  /// is embedded in every message — this location is NOT in the original BLE
  /// packet and is critical for responders.
  Future<void> _sendSmsSafe(PendingEvent pe, {VictimProfile? victimProfile}) async {
    // --- Build recipient list -------------------------------------------
    final List<EmergencyContact> contacts = [];

    if (victimProfile != null && victimProfile.contacts.isNotEmpty) {
      // Victim's registered emergency contacts (sorted by priority).
      for (final c in victimProfile.contacts) {
        final phone = c.phone;
        if (phone != null && phone.isNotEmpty) {
          contacts.add(EmergencyContact(
            name: c.name ?? 'Emergency Contact',
            phone: phone,
          ));
        }
      }
    }

    // Escalation operator always gets a direct device copy.
    if (kEscalationPhone.isNotEmpty) {
      contacts.add(EmergencyContact(
        name: 'Emergency Operator',
        phone: kEscalationPhone,
      ));
    }

    // Last resort: no profile and no escalation number configured.
    if (contacts.isEmpty) {
      kSmsDemoNumber
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .forEach((n) => contacts.add(EmergencyContact(name: 'SOS Alert', phone: n)));
    }

    if (contacts.isEmpty) {
      debugPrint('[BackgroundRelay] Device SMS: no valid targets for ${pe.id}');
      return;
    }

    // --- Build victim info line for message body -----------------------
    String? victimInfo;
    if (victimProfile != null) {
      final parts = <String>[];
      if (victimProfile.name?.isNotEmpty ?? false) {
        parts.add('Victim: ${victimProfile.name}');
      }
      if (victimProfile.phone?.isNotEmpty ?? false) {
        parts.add('Phone: ${victimProfile.phone}');
      }
      final blood = victimProfile.medical?.bloodGroup;
      if (blood?.isNotEmpty ?? false) { parts.add('Blood group: $blood'); }
      final allergies = victimProfile.medical?.allergies;
      if (allergies?.isNotEmpty ?? false) { parts.add('Allergies: $allergies'); }
      final conditions = victimProfile.medical?.conditions;
      if (conditions?.isNotEmpty ?? false) { parts.add('Conditions: $conditions'); }
      if (parts.isNotEmpty) { victimInfo = parts.join('\n'); }
    }

    debugPrint(
      '[BackgroundRelay] Device SMS for ${pe.id} | '
      'recipients=${contacts.length} '
      'numbers=[${contacts.map((c) => c.phone).join(', ')}]',
    );

    // --- Build SosEvent for SmsFallbackService -------------------------
    final event = SosEvent(
      id: pe.id,
      bleUid: Uint8List(6),
      flags: pe.flags,
      sequence: pe.sequence,
      timestamp: DateTime.fromMillisecondsSinceEpoch(pe.timestamp, isUtc: true),
      receiverLocation: ReceiverLocation(lat: pe.receiverLat, lon: pe.receiverLon),
    );

    // --- Retry loop ----------------------------------------------------
    for (int attempt = 0; attempt < kSmsMaxRetries; attempt++) {
      try {
        debugPrint(
          '[BackgroundRelay] SMS attempt ${attempt + 1}/$kSmsMaxRetries | id=${pe.id}',
        );

        smsService.emergencyContacts = contacts;
        smsService.enabled = true;

        final sent = await smsService.sendSos(event, victimInfo: victimInfo);
        debugPrint('[BackgroundRelay] Device SMS sent=$sent for ${pe.id}');

        if (sent > 0) {
          await pendingDb.markSmsSent(pe.id);
          debugPrint(
            '[BackgroundRelay] Device SMS OK for ${pe.id} after attempt ${attempt + 1} '
            '($sent/${contacts.length} delivered)',
          );
          return;
        }
      } catch (e) {
        debugPrint('[BackgroundRelay] SMS attempt ${attempt + 1} threw: $e');
      }

      // Exponential backoff before retry.
      if (attempt < kSmsMaxRetries - 1) {
        final delay = kSmsRetryBackoff * (attempt + 1);
        debugPrint('[BackgroundRelay] SMS retry backoff: ${delay.inSeconds}s');
        await Future<void>.delayed(delay);
      }
    }

    debugPrint('[BackgroundRelay] Device SMS FAILED all $kSmsMaxRetries attempts for ${pe.id}');
  }

  // ---------------------------------------------------------------------------
  // BLE re-broadcast
  // ---------------------------------------------------------------------------

  void _rebroadcast(CoreSosPacket packet) {
    final newTtl = packet.ttl - 1;
    if (newTtl <= 0) {
      debugPrint(
        '[BackgroundRelay] Not rebroadcasting — TTL would be $newTtl | '
        'uid=${packet.bleUidHex} seq=${packet.sequence}',
      );
      return;
    }
    debugPrint(
      '[BackgroundRelay] Rebroadcasting via BLE | uid=${packet.bleUidHex} '
      'seq=${packet.sequence} ttl=$newTtl',
    );
    try {
      final relayPacket = CoreSosPacket(
        version: packet.version,
        flags: packet.flags,
        bleUid: Uint8List.fromList(packet.bleUid),
        sequence: packet.sequence,
        ttl: newTtl,
      );
      advertiser.broadcastCoreSos(relayPacket);
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
