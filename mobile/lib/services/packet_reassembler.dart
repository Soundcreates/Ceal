/// Packet Reassembler — collects BLE packet fragments and assembles
/// the complete SOS payload once all chunks have arrived.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:aftermath/core/constants.dart';
import 'package:aftermath/models/ble_packet.dart';
import 'package:aftermath/models/sos_event.dart';

/// Callback when a full SOS event has been reassembled.
typedef OnSosReassembled = void Function(SosEvent event, String sourceDeviceId);

class PacketReassembler {
  PacketReassembler({this.onSosReassembled});

  OnSosReassembled? onSosReassembled;

  /// Buffer: deviceId → (sequence → payload).
  final Map<String, Map<int, Uint8List>> _buffer = {};

  /// Expected total chunks per device.
  final Map<String, int> _expectedChunks = {};

  /// Timers to auto-flush partial buffers.
  final Map<String, Timer> _timeouts = {};

  /// SOS IDs we have already fully reassembled (deduplication).
  final Set<String> _seenIds = {};

  /// Timeout for partial reassembly before discarding.
  static const Duration _reassemblyTimeout = Duration(seconds: 5);

  // -------------------------------------------------------------------------
  // API
  // -------------------------------------------------------------------------

  /// Feed a new [packet] from [deviceId] into the reassembly buffer.
  void addPacket(BlePacket packet, String deviceId) {
    _buffer.putIfAbsent(deviceId, () => {});
    _expectedChunks[deviceId] = packet.totalChunks;
    _buffer[deviceId]![packet.sequence] = Uint8List.fromList(packet.payload);

    // Reset the reassembly timeout.
    _timeouts[deviceId]?.cancel();
    _timeouts[deviceId] = Timer(_reassemblyTimeout, () {
      debugPrint(
          '[PacketReassembler] Timeout for $deviceId — flushing partial.');
      _tryReassemble(deviceId, allowPartial: true);
    });

    // Try immediate reassembly if all chunks present.
    if (_buffer[deviceId]!.length == packet.totalChunks) {
      _tryReassemble(deviceId);
    }
  }

  // -------------------------------------------------------------------------
  // Reassembly
  // -------------------------------------------------------------------------

  void _tryReassemble(String deviceId, {bool allowPartial = false}) {
    final chunks = _buffer[deviceId];
    final total = _expectedChunks[deviceId] ?? 0;

    if (chunks == null || chunks.isEmpty) return;

    if (!allowPartial && chunks.length < total) return;

    // Build the full payload in sequence order.
    final sortedKeys = chunks.keys.toList()..sort();
    final fullPayload = Uint8List(sortedKeys.length * kBlePayloadSize);

    for (int i = 0; i < sortedKeys.length; i++) {
      final chunkData = chunks[sortedKeys[i]]!;
      fullPayload.setRange(
        i * kBlePayloadSize,
        i * kBlePayloadSize + chunkData.length,
        chunkData,
      );
    }

    // Decode the compact GPS payload.
    try {
      final decoded = SosEvent.fromCompactPayload(fullPayload);

      // Build a dedup key from the device ID hash.
      final dedupKey =
          '${decoded.deviceIdHash[0]}:${decoded.deviceIdHash[1]}:$deviceId';

      if (_seenIds.contains(dedupKey)) {
        debugPrint('[PacketReassembler] Duplicate $dedupKey, skipping.');
        _cleanup(deviceId);
        return;
      }
      _seenIds.add(dedupKey);

      // Schedule removal from seen set after the dedup window.
      Timer(kDeduplicationWindow, () => _seenIds.remove(dedupKey));

      final event = SosEvent(
        id: dedupKey,
        deviceIdHash: decoded.deviceIdHash,
        latitude: decoded.latitude,
        longitude: decoded.longitude,
        timestamp: DateTime.now().toUtc(),
      );

      debugPrint('[PacketReassembler] Reassembled SOS: $event');
      onSosReassembled?.call(event, deviceId);
    } catch (e) {
      debugPrint('[PacketReassembler] Decode error: $e');
    }

    _cleanup(deviceId);
  }

  void _cleanup(String deviceId) {
    _buffer.remove(deviceId);
    _expectedChunks.remove(deviceId);
    _timeouts[deviceId]?.cancel();
    _timeouts.remove(deviceId);
  }

  // -------------------------------------------------------------------------
  // Dispose
  // -------------------------------------------------------------------------

  void dispose() {
    for (final t in _timeouts.values) {
      t.cancel();
    }
    _timeouts.clear();
    _buffer.clear();
    _expectedChunks.clear();
    _seenIds.clear();
  }
}
