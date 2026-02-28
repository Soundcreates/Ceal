/// BLE Scanner Service — listens for nearby SOS BLE advertisements.
///
/// Uses [flutter_blue_plus] to scan for devices advertising the AfterMath
/// service UUID and extracts raw packet data from the advertisement.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'package:aftermath/core/constants.dart';
import 'package:aftermath/models/ble_packet.dart';

/// Callback invoked when a valid SOS packet is received.
typedef OnPacketReceived = void Function(BlePacket packet, String deviceId);

class BleScannerService {
  BleScannerService({this.onPacketReceived});

  /// External callback for each decoded packet.
  OnPacketReceived? onPacketReceived;

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

    // Try manufacturer-specific data first (Android).
    for (final entry in advData.manufacturerData.entries) {
      if (entry.key == kManufacturerId) {
        final raw = Uint8List.fromList(entry.value);
        _tryDecode(raw, deviceId);
        return;
      }
    }

    // Fallback: check service data (iOS / GATT-based advertisements).
    for (final entry in advData.serviceData.entries) {
      if (entry.key.toString().toUpperCase().contains('BEEF')) {
        final raw = Uint8List.fromList(entry.value);
        _tryDecode(raw, deviceId);
        return;
      }
    }
  }

  void _tryDecode(Uint8List raw, String deviceId) {
    if (raw.length < kBlePacketSize) {
      debugPrint(
          '[BleScannerService] Packet too short (${raw.length}B), ignoring.');
      return;
    }

    try {
      final packet = BlePacket.fromBytes(raw);
      debugPrint('[BleScannerService] Received $packet from $deviceId');
      onPacketReceived?.call(packet, deviceId);
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
