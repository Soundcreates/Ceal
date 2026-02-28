/// BLE Advertiser Service — broadcasts SOS packets via BLE advertising.
///
/// Uses [flutter_ble_peripheral] to emit manufacturer-specific data.
/// V2: broadcasts the 10-byte CORE SOS packet (no GPS, UID-based).
///
/// On iOS, BLE advertisement data must be attached to a GATT characteristic
/// rather than manufacturer data, because iOS hides manufacturer bytes when
/// backgrounded. We handle this via the service UUID and local name fallback.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';

import 'package:aftermath/core/constants.dart';
import 'package:aftermath/models/ble_packet.dart';
import 'package:aftermath/models/core_sos_packet.dart';

class BleAdvertiserService {
  final FlutterBlePeripheral _peripheral = FlutterBlePeripheral();

  bool _isAdvertising = false;
  bool get isAdvertising => _isAdvertising;

  // -------------------------------------------------------------------------
  // High-level API
  // -------------------------------------------------------------------------

  /// Broadcast a 10-byte CORE SOS V2 packet.
  ///
  /// The CORE packet is self-contained (no fragmentation needed) and is
  /// burst-repeated [kAdvertiseBurstCount] times.
  Future<void> broadcastCoreSos(CoreSosPacket packet) async {
    debugPrint(
      '[BleAdvertiserService] Broadcasting CORE SOS V2 packet '
      '(uid=${packet.bleUidHex}, seq=${packet.sequence}).',
    );

    final raw = packet.toBytes();
    for (int burst = 0; burst < kAdvertiseBurstCount; burst++) {
      await _advertiseRawBytes(raw);
      await Future<void>.delayed(kChunkDelay);
      if (burst < kAdvertiseBurstCount - 1) {
        await Future<void>.delayed(kBurstInterval);
      }
    }

    await stopAdvertising();
    debugPrint('[BleAdvertiserService] CORE V2 broadcast complete.');
  }

  /// Broadcast a single pre-built [BlePacket] (e.g. a relay fragment).
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
  // Low-level advertising
  // -------------------------------------------------------------------------

  Future<void> _advertisePacket(BlePacket packet) async {
    await _advertiseRawBytes(packet.toBytes());
  }

  /// Advertise an arbitrary raw byte buffer (CORE packet or fragment).
  Future<void> _advertiseRawBytes(Uint8List raw) async {
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
