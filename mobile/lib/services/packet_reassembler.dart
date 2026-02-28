/// Packet Reassembler — V2 privacy-first UID-based deduplication.
///
/// The primary path is [addCorePacket] which takes a 10-byte CORE V2 packet
/// containing a static BLE UID + sequence counter. Deduplication key is
/// `uid:<hex>:<sequence>`.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:aftermath/core/constants.dart';
import 'package:aftermath/models/core_sos_packet.dart';
import 'package:aftermath/models/sos_event.dart';

/// Callback when a SOS event has been decoded / reassembled.
typedef OnSosReassembled = void Function(
    SosEvent event, String sourceDeviceId, int rssi);

class PacketReassembler {
  PacketReassembler({this.onSosReassembled});

  OnSosReassembled? onSosReassembled;

  /// SOS dedup keys we have already processed.
  final Set<String> _seenIds = {};

  // -------------------------------------------------------------------------
  // API
  // -------------------------------------------------------------------------

  /// Feed a 10-byte CORE SOS V2 packet directly.
  ///
  /// Dedup key = `uid:<bleUidHex>:<sequence>`.
  /// Applies deduplication and immediately fires [onSosReassembled].
  void addCorePacket(CoreSosPacket packet, String deviceId, int rssi) {
    final dedupKey = 'uid:${packet.bleUidHex}:${packet.sequence}';

    if (_seenIds.contains(dedupKey)) {
      debugPrint('[PacketReassembler] Duplicate CORE $dedupKey, skipping.');
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

    debugPrint('[PacketReassembler] CORE V2 SOS decoded: $event');
    onSosReassembled?.call(event, deviceId, rssi);
  }

  // -------------------------------------------------------------------------
  // Dispose
  // -------------------------------------------------------------------------

  void dispose() {
    _seenIds.clear();
  }
}
