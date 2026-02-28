/// BLE scanner service for SOS advertisements.
library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'package:aftermath/core/constants.dart';
import 'package:aftermath/models/ble_packet.dart';
import 'package:aftermath/models/core_sos_packet.dart';

typedef OnPacketReceived = void Function(BlePacket packet, String deviceId, int rssi);
typedef OnCorePacketReceived = void Function(CoreSosPacket packet, String deviceId, int rssi);

class BleScannerService {
  BleScannerService({this.onPacketReceived, this.onCorePacketReceived});

  OnPacketReceived? onPacketReceived;
  OnCorePacketReceived? onCorePacketReceived;

  StreamSubscription<List<ScanResult>>? _scanSub;
  bool _isScanning = false;

  bool get isScanning => _isScanning;

  Future<void> startScanning() async {
    if (_isScanning) return;

    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      debugPrint('[BleScannerService] Bluetooth adapter is $adapterState');
      return;
    }

    _isScanning = true;

    await FlutterBluePlus.startScan(
      withServices: [Guid(kSosServiceUuid)],
      androidScanMode: AndroidScanMode.balanced,
      continuousUpdates: true,
    );

    _scanSub = FlutterBluePlus.scanResults.listen(
      _onScanResults,
      onError: (Object err) => debugPrint('[BleScannerService] Scan error: $err'),
    );

    debugPrint('[BleScannerService] Scanning started.');
  }

  Future<void> stopScanning() async {
    if (!_isScanning) return;
    await FlutterBluePlus.stopScan();
    await _scanSub?.cancel();
    _scanSub = null;
    _isScanning = false;
    debugPrint('[BleScannerService] Scanning stopped.');
  }

  void _onScanResults(List<ScanResult> results) {
    for (final result in results) {
      _processResult(result);
    }
  }

  void _processResult(ScanResult result) {
    final advData = result.advertisementData;
    final deviceId = result.device.remoteId.str;
    final rssi = result.rssi;

    for (final entry in advData.manufacturerData.entries) {
      if (entry.key == kManufacturerId) {
        _tryDecode(Uint8List.fromList(entry.value), deviceId, rssi);
        return;
      }
    }

    for (final entry in advData.serviceData.entries) {
      if (entry.key.toString().toUpperCase().contains('BEEF')) {
        _tryDecode(Uint8List.fromList(entry.value), deviceId, rssi);
        return;
      }
    }
  }

  void _tryDecode(Uint8List raw, String deviceId, int rssi) {
    if (raw.length >= kCorePacketSize) {
      _tryDecodeCorePacket(raw, deviceId, rssi);
      return;
    }
    if (raw.length >= kBlePacketSize) {
      _tryDecodeFragment(raw, deviceId, rssi);
      return;
    }
    debugPrint('[BleScannerService] Packet too short (${raw.length}B), ignoring.');
  }

  void _tryDecodeCorePacket(Uint8List raw, String deviceId, int rssi) {
    try {
      final packet = CoreSosPacket.fromBytes(raw);
      onCorePacketReceived?.call(packet, deviceId, rssi);
    } catch (_) {
      _tryDecodeFragment(raw, deviceId, rssi);
    }
  }

  void _tryDecodeFragment(Uint8List raw, String deviceId, int rssi) {
    try {
      final packet = BlePacket.fromBytes(raw);
      onPacketReceived?.call(packet, deviceId, rssi);
    } catch (e) {
      debugPrint('[BleScannerService] Failed to decode packet: $e');
    }
  }

  Future<void> dispose() async {
    await stopScanning();
  }
}
