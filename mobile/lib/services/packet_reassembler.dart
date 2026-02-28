/// Packet reassembler / deduplicator for incoming SOS packets.
library;

import 'dart:async';
import 'package:flutter/foundation.dart';

import 'package:aftermath/core/constants.dart';
import 'package:aftermath/models/ble_packet.dart';
import 'package:aftermath/models/core_sos_packet.dart';
import 'package:aftermath/models/sos_event.dart';

typedef OnSosReassembled = void Function(SosEvent event, String sourceDeviceId, int rssi);

class PacketReassembler {
  PacketReassembler({this.onSosReassembled});

  OnSosReassembled? onSosReassembled;

  final Set<String> _seenIds = {};

  // Legacy fragment path placeholders.
  final Map<String, Map<int, Uint8List>> _buffer = {};
  final Map<String, int> _expectedChunks = {};
  final Map<String, Timer> _timeouts = {};

  void addCorePacket(CoreSosPacket packet, String deviceId, int rssi) {
    final dedupKey = 'uid:${packet.bleUidHex}:${packet.sequence}';
    if (_seenIds.contains(dedupKey)) {
      return;
    }

    _seenIds.add(dedupKey);
    Timer(kDeduplicationWindow, () => _seenIds.remove(dedupKey));

    final event = SosEvent(
      id: dedupKey,
      bleUid: Uint8List.fromList(packet.bleUid),
      flags: packet.flags,
      sequence: packet.sequence,
      timestamp: DateTime.now().toUtc(),
      rssi: rssi,
    );

    onSosReassembled?.call(event, deviceId, rssi);
  }

  void addPacket(BlePacket packet, String deviceId, int rssi) {
    debugPrint('[PacketReassembler] Ignoring legacy fragment packet from $deviceId: $packet');
  }

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
