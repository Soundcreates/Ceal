/// Mesh relay service for received SOS packets.
library;

import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';

import 'package:aftermath/core/constants.dart';
import 'package:aftermath/models/core_sos_packet.dart';
import 'package:aftermath/models/sos_event.dart';
import 'package:aftermath/services/backend_service.dart';
import 'package:aftermath/services/ble_advertiser_service.dart';
import 'package:aftermath/services/location_service.dart';
import 'package:aftermath/services/queue_service.dart';

class MeshRelayService {
  MeshRelayService({
    required this.advertiser,
    required this.backendService,
    required this.queueService,
    required this.locationService,
  }) {
    _flushTimer = Timer.periodic(const Duration(seconds: 30), (_) => flushQueue());
  }

  final BleAdvertiserService advertiser;
  final BackendService backendService;
  final QueueService queueService;
  final LocationService locationService;

  final Set<String> _relayedIds = {};
  final List<Timer> _pendingTimers = [];
  late final Timer _flushTimer;
  final Random _rng = Random();

  Future<void> onSosReceived(SosEvent event, String sourceDeviceId, int rssi) async {
    if (_relayedIds.contains(event.id) || event.isExpired) {
      return;
    }

    // TTL guard — if hops already at max, don't relay further.
    if (event.relayHops >= kDefaultTtl) {
      debugPrint(
        '[MeshRelayService] TTL EXPIRED — ${event.id} hops=${event.relayHops} | dropping',
      );
      return;
    }

    _relayedIds.add(event.id);
    _pendingTimers.add(Timer(kDeduplicationWindow, () => _relayedIds.remove(event.id)));

    event.rssi = rssi;
    final pos = await locationService.getCurrentPosition();
    if (pos != null) {
      event.receiverLocation = ReceiverLocation(
        lat: pos.latitude,
        lon: pos.longitude,
        accuracy: pos.accuracy,
      );
    }

    await queueService.enqueue(event);
    unawaited(_uploadToBackend(event));

    final jitter = Duration(milliseconds: 100 + _rng.nextInt(400));
    _pendingTimers.add(Timer(jitter, () => _rebroadcast(event)));

    debugPrint(
      '[MeshRelayService] Relayed event ${event.id} from $sourceDeviceId '
      'hops=${event.relayHops}',
    );
  }

  Future<void> _uploadToBackend(SosEvent event) async {
    try {
      final ok = await backendService.ingestSos(event);
      if (!ok) return;
      event.status = SosStatus.relayed;
      await queueService.markUploaded(event.id);
    } catch (e) {
      debugPrint('[MeshRelayService] Backend upload failed: $e');
    }
  }

  Future<void> _rebroadcast(SosEvent event) async {
    final newHops = event.relayHops + 1;
    final newTtl = kDefaultTtl - newHops;
    if (newTtl <= 0) {
      debugPrint(
        '[MeshRelayService] Not rebroadcasting — TTL would be $newTtl | ${event.id}',
      );
      return;
    }
    try {
      final corePacket = CoreSosPacket(
        flags: event.flags,
        bleUid: Uint8List.fromList(event.bleUid),
        sequence: event.sequence,
        ttl: newTtl,
      );
      await advertiser.broadcastCoreSos(corePacket);
    } catch (e) {
      debugPrint('[MeshRelayService] Rebroadcast failed: $e');
    }
  }

  Future<void> flushQueue() async {
    final pending = await queueService.pendingEvents();
    for (final event in pending) {
      await _uploadToBackend(event);
    }
  }

  void dispose() {
    _flushTimer.cancel();
    for (final t in _pendingTimers) {
      t.cancel();
    }
    _pendingTimers.clear();
    _relayedIds.clear();
  }
}
