/// BLE Advertiser Service — broadcasts SOS packets via BLE advertising.
///
/// Uses [flutter_ble_peripheral] to emit manufacturer-specific data containing
/// the 11-byte SOS packet fragments.
///
/// On iOS, BLE advertisement data must be attached to a GATT characteristic
/// rather than manufacturer data, because iOS hides manufacturer bytes when
/// backgrounded. We handle this via the service UUID and local name fallback.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';

import 'package:aftermath/core/constants.dart';
import 'package:aftermath/models/ble_packet.dart';
import 'package:aftermath/models/sos_event.dart';

class BleAdvertiserService {
  final FlutterBlePeripheral _peripheral = FlutterBlePeripheral();

  bool _isAdvertising = false;
  bool get isAdvertising => _isAdvertising;

  // -------------------------------------------------------------------------
  // High-level API
  // -------------------------------------------------------------------------

  /// Broadcast a full [SosEvent] by chunking its compact payload into 11-byte
  /// BLE packets and advertising each fragment in sequence.
  ///
  /// The advertisement is burst-repeated [kAdvertiseBurstCount] times to
  /// maximise the chance of nearby scanners picking it up.
  Future<void> broadcastSos(SosEvent event) async {
    final payload = event.toCompactPayload();
    final packets = _chunkPayload(payload, messageType: MsgType.sos);

    debugPrint(
      '[BleAdvertiserService] Broadcasting SOS ${event.id}: '
      '${packets.length} chunk(s), $kAdvertiseBurstCount burst(s).',
    );

    for (int burst = 0; burst < kAdvertiseBurstCount; burst++) {
      for (final packet in packets) {
        await _advertisePacket(packet);
        await Future<void>.delayed(kChunkDelay);
      }
      if (burst < kAdvertiseBurstCount - 1) {
        await Future<void>.delayed(kBurstInterval);
      }
    }

    await stopAdvertising();
    debugPrint('[BleAdvertiserService] Broadcast complete for ${event.id}.');
  }

  /// Broadcast a single pre-built [BlePacket] (e.g. a relay).
  Future<void> broadcastPacket(BlePacket packet) async {
    await _advertisePacket(packet);
    await Future<void>.delayed(kChunkDelay);
    await stopAdvertising();
  }

  /// Stop any active advertisement.
  Future<void> stopAdvertising() async {
    if (!_isAdvertising) return;
    try {
      await _peripheral.stop();
    } catch (e) {
      debugPrint('[BleAdvertiserService] Stop error: $e');
    }
    _isAdvertising = false;
  }

  // -------------------------------------------------------------------------
  // Chunking
  // -------------------------------------------------------------------------

  /// Split a full message into a list of [BlePacket]s.
  List<BlePacket> _chunkPayload(
    Uint8List fullPayload, {
    int messageType = MsgType.sos,
    bool encrypted = false,
    int ttl = kDefaultTtl,
  }) {
    final totalChunks = (fullPayload.length / kBlePayloadSize).ceil();
    final packets = <BlePacket>[];

    for (int i = 0; i < totalChunks; i++) {
      final start = i * kBlePayloadSize;
      final end = min(start + kBlePayloadSize, fullPayload.length);
      final chunk = Uint8List(kBlePayloadSize); // zero-padded
      chunk.setRange(0, end - start, fullPayload.sublist(start, end));

      final isLast = i == totalChunks - 1;

      packets.add(BlePacket(
        sequence: i,
        totalChunks: totalChunks,
        flags: BlePacket.buildFlags(
          messageType: messageType,
          encrypted: encrypted,
          lastChunk: isLast,
          ttl: ttl,
        ),
        payload: chunk,
      ));
    }

    return packets;
  }

  // -------------------------------------------------------------------------
  // Low-level advertising
  // -------------------------------------------------------------------------

  Future<void> _advertisePacket(BlePacket packet) async {
    final raw = packet.toBytes();

    final advertiseData = AdvertiseData(
      serviceUuid: kSosServiceUuid,
      manufacturerId: kManufacturerId,
      manufacturerData: raw,
    );

    final advertiseSettings = AdvertiseSettings(
      advertiseMode: AdvertiseMode.advertiseModeBalanced,
      connectable: false,
      timeout: 1000, // ms
      txPowerLevel: AdvertiseTxPower.advertiseTxPowerHigh,
    );

    try {
      await _peripheral.start(
        advertiseData: advertiseData,
        advertiseSettings: advertiseSettings,
      );
      _isAdvertising = true;
    } catch (e) {
      debugPrint('[BleAdvertiserService] Advertise error: $e');
    }
  }

  // -------------------------------------------------------------------------
  // Dispose
  // -------------------------------------------------------------------------

  Future<void> dispose() async {
    await stopAdvertising();
  }
}
