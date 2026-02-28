/// BLE Scanner Service — listens for nearby SOS BLE advertisements.
///
/// Uses [flutter_blue_plus] to scan for devices advertising the AfterMath
/// service UUID and extracts raw packet data from the advertisement.
///
/// V2: passes RSSI alongside decoded packets so the relay service can
/// include signal-strength in the backend payload.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'package:aftermath/core/constants.dart';
import 'package:aftermath/models/ble_packet.dart';
import 'package:aftermath/models/core_sos_packet.dart';

/// Callback invoked when a valid fragment packet is received.
typedef OnPacketReceived = void Function(
    BlePacket packet, String deviceId, int rssi);

/// Callback invoked when a valid 10-byte CORE SOS V2 packet is received.
typedef OnCorePacketReceived = void Function(
    CoreSosPacket packet, String deviceId, int rssi);

class BleScannerService {
  BleScannerService({this.onPacketReceived, this.onCorePacketReceived});

  /// External callback for each decoded fragment packet.
  OnPacketReceived? onPacketReceived;

  /// External callback for each decoded 10-byte CORE SOS V2 packet.
  OnCorePacketReceived? onCorePacketReceived;

  StreamSubscription<List<ScanResult>>? _scanSub;
  bool _isScanning = false;

  bool get isScanning => _isScanning;

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  /// Start scanning for BLE SOS advertisements.
  ///
  /// Filters on the AfterMath service UUID to avoid noise from unrelated
  /// peripherals.
  Future<void> startScanning() async {
    if (_isScanning) return;

    // Ensure Bluetooth adapter is on.
    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      debugPrint('[BleScannerService] Bluetooth adapter is $adapterState');
      return;
    }

    _isScanning = true;

    // Start the actual BLE scan.
    await FlutterBluePlus.startScan(
      withServices: [Guid(kSosServiceUuid)],
      androidScanMode: AndroidScanMode.balanced,
      continuousUpdates: true,
    );

    _scanSub = FlutterBluePlus.scanResults.listen(
      _onScanResults,
      onError: (Object err) {
        debugPrint('[BleScannerService] Scan error: $err');
      },
    );

    debugPrint('[BleScannerService] Scanning started.');
  }

  /// Stop the BLE scan.
  Future<void> stopScanning() async {
    if (!_isScanning) return;
    await FlutterBluePlus.stopScan();
    await _scanSub?.cancel();
    _scanSub = null;
    _isScanning = false;
    debugPrint('[BleScannerService] Scanning stopped.');
  }

  // -------------------------------------------------------------------------
  // Result processing
  // -------------------------------------------------------------------------

  void _onScanResults(List<ScanResult> results) {
    for (final result in results) {
      _processResult(result);
    }
  }

  void _processResult(ScanResult result) {
    final advData = result.advertisementData;
    final deviceId = result.device.remoteId.str;
    final rssi = result.rssi;

    // Try manufacturer-specific data first (Android).
    for (final entry in advData.manufacturerData.entries) {
      if (entry.key == kManufacturerId) {
        final raw = Uint8List.fromList(entry.value);
        _tryDecode(raw, deviceId, rssi);
        return;
      }
    }

    // Fallback: check service data (iOS / GATT-based advertisements).
    for (final entry in advData.serviceData.entries) {
      if (entry.key.toString().toUpperCase().contains('BEEF')) {
        final raw = Uint8List.fromList(entry.value);
        _tryDecode(raw, deviceId, rssi);
        return;
      }
    }
  }

  void _tryDecode(Uint8List raw, String deviceId, int rssi) {
    // Length-based dispatch: 10 bytes → CORE V2 packet, 13 bytes → fragment.
    if (raw.length >= kBlePacketSize) {
      _tryDecodeFragment(raw, deviceId, rssi);
    } else if (raw.length >= kCorePacketSize) {
      _tryDecodeCorePacket(raw, deviceId, rssi);
    } else {
      debugPrint(
          '[BleScannerService] Packet too short (${raw.length}B), ignoring.');
    }
  }

  void _tryDecodeCorePacket(Uint8List raw, String deviceId, int rssi) {
    try {
      final packet = CoreSosPacket.fromBytes(raw);
      debugPrint(
          '[BleScannerService] Received CORE V2 from $deviceId (RSSI=$rssi)');
      onCorePacketReceived?.call(packet, deviceId, rssi);
    } catch (e) {
      debugPrint('[BleScannerService] Failed to decode CORE packet: $e');
    }
  }

  void _tryDecodeFragment(Uint8List raw, String deviceId, int rssi) {
    try {
      final packet = BlePacket.fromBytes(raw);
      debugPrint('[BleScannerService] Received $packet from $deviceId');
      onPacketReceived?.call(packet, deviceId, rssi);
    } catch (e) {
      debugPrint('[BleScannerService] Failed to decode packet: $e');
    }
  }

  // -------------------------------------------------------------------------
  // Dispose
  // -------------------------------------------------------------------------

  Future<void> dispose() async {
    await stopScanning();
  }
}
