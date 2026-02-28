/// Mesh Relay Service — epidemic (flooding) protocol implementation.
///
/// When a nearby device's SOS broadcast is received, this service:
/// 1. Deduplicates (drops already-seen IDs).
/// 2. Stores the event in the local SQLite queue.
/// 3. Attempts to upload to the backend.
/// 4. Rebroadcasts via BLE after a random jitter delay.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:aftermath/core/constants.dart';
import 'package:aftermath/models/sos_event.dart';
import 'package:aftermath/services/ble_advertiser_service.dart';
import 'package:aftermath/services/backend_service.dart';
import 'package:aftermath/services/queue_service.dart';

class MeshRelayService {
  MeshRelayService({
    required this.advertiser,
    required this.backendService,
    required this.queueService,
  }) {
    _flushTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => flushQueue(),
    );
  }

  final BleAdvertiserService advertiser;
  final BackendService backendService;
  final QueueService queueService;

  /// Set of SOS IDs that have already been relayed by this device.
  final Set<String> _relayedIds = {};

  /// Pending relay timers (so we can cancel on dispose).
  final List<Timer> _pendingTimers = [];

  /// Periodic queue-flush timer.
  late final Timer _flushTimer;

  final Random _rng = Random();

  // -------------------------------------------------------------------------
  // API
  // -------------------------------------------------------------------------

  /// Called by the [PacketReassembler] when a full SOS is assembled from
  /// an incoming BLE broadcast.
  Future<void> onSosReceived(SosEvent event, String sourceDeviceId) async {
    // 1. Dedup check.
    if (_relayedIds.contains(event.id)) {
      debugPrint('[MeshRelayService] Already relayed ${event.id}, skipping.');
      return;
    }
    if (event.isExpired) {
      debugPrint('[MeshRelayService] Event ${event.id} expired, dropping.');
      return;
    }

    _relayedIds.add(event.id);

    // Schedule cleanup of dedup entry.
    _pendingTimers.add(
      Timer(kDeduplicationWindow, () => _relayedIds.remove(event.id)),
    );

    // 2. Persist to local queue.
    await queueService.enqueue(event);
    debugPrint('[MeshRelayService] Queued ${event.id} for relay.');

    // 3. Attempt backend upload (non-blocking).
    _uploadToBackend(event);

    // 4. Schedule BLE rebroadcast with random jitter.
    final jitter = Duration(milliseconds: 100 + _rng.nextInt(400));
    _pendingTimers.add(
      Timer(jitter, () => _rebroadcast(event)),
    );
  }

  // -------------------------------------------------------------------------
  // Backend upload
  // -------------------------------------------------------------------------

  Future<void> _uploadToBackend(SosEvent event) async {
    try {
      final ok = await backendService.ingestSos(event);
      if (ok) {
        event.status = SosStatus.relayed;
        await queueService.markUploaded(event.id);
        debugPrint('[MeshRelayService] Uploaded ${event.id} to backend.');
      }
    } catch (e) {
      debugPrint('[MeshRelayService] Backend upload failed: $e');
      // Will be retried by the queue flush job.
    }
  }

  // -------------------------------------------------------------------------
  // BLE rebroadcast
  // -------------------------------------------------------------------------

  Future<void> _rebroadcast(SosEvent event) async {
    event.relayHops++;
    debugPrint(
      '[MeshRelayService] Rebroadcasting ${event.id} (hop ${event.relayHops}).',
    );
    try {
      await advertiser.broadcastSos(event);
    } catch (e) {
      debugPrint('[MeshRelayService] Rebroadcast failed: $e');
    }
  }

  // -------------------------------------------------------------------------
  // Queue flush (call periodically / on connectivity change)
  // -------------------------------------------------------------------------

  /// Attempt to upload all queued events that haven't been sent yet.
  Future<void> flushQueue() async {
    final pending = await queueService.pendingEvents();
    for (final event in pending) {
      await _uploadToBackend(event);
    }
  }

  // -------------------------------------------------------------------------
  // Dispose
  // -------------------------------------------------------------------------

  void dispose() {
    _flushTimer.cancel();
    for (final t in _pendingTimers) {
      t.cancel();
    }
    _pendingTimers.clear();
    _relayedIds.clear();
  }
}
