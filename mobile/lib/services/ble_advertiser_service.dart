/// BLE advertiser service for SOS packets.
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

  Future<void> broadcastCoreSos(CoreSosPacket packet) async {
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

  Future<void> broadcastPacket(BlePacket packet) async {
    await _advertiseRawBytes(packet.toBytes());
    await Future<void>.delayed(kChunkDelay);
    await stopAdvertising();
  }

  Future<void> stopAdvertising() async {
    if (!_isAdvertising) return;
    try {
      await _peripheral.stop();
    } catch (e) {
      debugPrint('[BleAdvertiserService] Stop error: $e');
    }
    _isAdvertising = false;
  }

  Future<void> _advertiseRawBytes(Uint8List raw) async {
    final advertiseData = AdvertiseData(
      serviceUuid: kSosServiceUuid,
      manufacturerId: kManufacturerId,
      manufacturerData: raw,
    );

    final advertiseSettings = AdvertiseSettings(
      advertiseMode: AdvertiseMode.advertiseModeBalanced,
      connectable: false,
      timeout: 1000,
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

  Future<void> dispose() async {
    await stopAdvertising();
  }
}
