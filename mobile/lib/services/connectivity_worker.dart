/// Connectivity worker — monitors network state and drains the pending-events
/// queue when connectivity is restored.
///
/// Runs a periodic timer alongside a connectivity stream listener so events
/// are uploaded as soon as the device goes online.
library;

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import 'package:aftermath/core/poc_config.dart';
import 'package:aftermath/services/backend_service.dart';
import 'package:aftermath/services/pending_events_db.dart';
import 'package:aftermath/models/sos_event.dart';

class ConnectivityWorker {
  ConnectivityWorker({
    required this.pendingDb,
    required this.backendService,
  });

  final PendingEventsDb pendingDb;
  final BackendService backendService;

  StreamSubscription<List<ConnectivityResult>>? _connectSub;
  Timer? _periodicTimer;
  bool _draining = false;

  // ---------------------------------------------------------------------------
  // Start / Stop
  // ---------------------------------------------------------------------------

  void start() {
    // Listen for connectivity changes.
    _connectSub = Connectivity()
        .onConnectivityChanged
        .listen(_onConnectivityChanged);

    // Also drain periodically as a safety net.
    _periodicTimer = Timer.periodic(kQueueDrainInterval, (_) => drainQueue());

    debugPrint('[ConnectivityWorker] Started.');
  }

  void stop() {
    _connectSub?.cancel();
    _connectSub = null;
    _periodicTimer?.cancel();
    _periodicTimer = null;
    debugPrint('[ConnectivityWorker] Stopped.');
  }

  // ---------------------------------------------------------------------------
  // Connectivity callback
  // ---------------------------------------------------------------------------

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final hasNetwork = results.any((r) =>
        r == ConnectivityResult.wifi ||
        r == ConnectivityResult.mobile ||
        r == ConnectivityResult.ethernet);

    if (hasNetwork) {
      debugPrint('[ConnectivityWorker] Network available — draining queue.');
      drainQueue();
    }
  }

  // ---------------------------------------------------------------------------
  // Queue drain
  // ---------------------------------------------------------------------------

  /// Upload all pending events to the backend.
  Future<void> drainQueue() async {
    if (_draining) return; // prevent concurrent drains
    _draining = true;

    try {
      final pending = await pendingDb.pendingBackendEvents();
      if (pending.isEmpty) {
        _draining = false;
        return;
      }

      debugPrint('[ConnectivityWorker] Draining ${pending.length} pending events.');

      for (final pe in pending) {
        try {
          final event = _toSosEvent(pe);
          final ok = await backendService.ingestSos(event);
          if (ok) {
            await pendingDb.markSentToBackend(pe.id);
            debugPrint('[ConnectivityWorker] Uploaded ${pe.id}');
          } else {
            await pendingDb.updateLastAttempt(pe.id);
          }
        } catch (e) {
          debugPrint('[ConnectivityWorker] Upload error for ${pe.id}: $e');
          await pendingDb.updateLastAttempt(pe.id);
        }
      }
    } finally {
      _draining = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Check if the device currently has network connectivity.
  Future<bool> hasConnectivity() async {
    final results = await Connectivity().checkConnectivity();
    return results.any((r) =>
        r == ConnectivityResult.wifi ||
        r == ConnectivityResult.mobile ||
        r == ConnectivityResult.ethernet);
  }

  SosEvent _toSosEvent(PendingEvent pe) {
    final uidBytes = Uint8List(6);
    final hex = pe.uid;
    if (hex.length >= 12) {
      for (int i = 0; i < 6; i++) {
        uidBytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
      }
    }

    return SosEvent(
      id: pe.id,
      bleUid: uidBytes,
      flags: pe.flags,
      sequence: pe.sequence,
      timestamp: DateTime.fromMillisecondsSinceEpoch(pe.timestamp, isUtc: true),
      relayHops: pe.relayHops,
      receiverLocation: ReceiverLocation(lat: pe.receiverLat, lon: pe.receiverLon),
      rssi: pe.rssi,
    );
  }

  void dispose() => stop();
}
