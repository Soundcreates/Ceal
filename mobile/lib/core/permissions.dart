/// Centralised runtime permission handling for AfterMath.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// Result summary after requesting all required permissions.
class PermissionResult {
  const PermissionResult({
    required this.bluetooth,
    required this.location,
    required this.notification,
    required this.sms,
  });

  final bool bluetooth;
  final bool location;
  final bool notification;
  final bool sms;

  bool get allGranted => bluetooth && location && notification;

  @override
  String toString() =>
      'PermissionResult(bt=$bluetooth, loc=$location, notif=$notification, sms=$sms)';
}

class PermissionService {
  /// Request all permissions needed for full SOS functionality.
  Future<PermissionResult> requestAll() async {
    final bt = await _requestBluetooth();
    final loc = await _requestLocation();
    final notif = await _requestNotification();
    final sms = await _requestSms();
    return PermissionResult(
      bluetooth: bt,
      location: loc,
      notification: notif,
      sms: sms,
    );
  }

  // ---------------------------------------------------------------------------
  // Bluetooth
  // ---------------------------------------------------------------------------

  Future<bool> _requestBluetooth() async {
    if (Platform.isAndroid) {
      final statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.bluetoothAdvertise,
      ].request();
      return statuses.values.every((s) => s.isGranted);
    }
    // iOS: Bluetooth permission is requested implicitly by CoreBluetooth.
    // We still check the status.
    final status = await Permission.bluetooth.request();
    return status.isGranted;
  }

  // ---------------------------------------------------------------------------
  // Location
  // ---------------------------------------------------------------------------

  Future<bool> _requestLocation() async {
    final status = await Permission.locationWhenInUse.request();
    if (!status.isGranted) return false;
    // Optionally request background location (needed for background relay).
    if (Platform.isAndroid) {
      final bg = await Permission.locationAlways.request();
      debugPrint('Background location: $bg');
    }
    return true;
  }

  // ---------------------------------------------------------------------------
  // Notifications
  // ---------------------------------------------------------------------------

  Future<bool> _requestNotification() async {
    if (Platform.isAndroid) {
      final status = await Permission.notification.request();
      return status.isGranted;
    }
    // iOS handles notification permission via UNUserNotificationCenter;
    // flutter_local_notifications will prompt automatically.
    return true;
  }

  // ---------------------------------------------------------------------------
  // SMS
  //
  // Android 13+ and Play policy heavily restrict broad SMS permissions in many
  // app categories. We avoid proactively requesting SMS runtime permission
  // here; app-level fallback should use backend escalation and/or SMS composer.
  // ---------------------------------------------------------------------------

  Future<bool> _requestSms() async {
    return true;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Check if Bluetooth is currently enabled on the device.
  Future<bool> isBluetoothEnabled() async {
    final status = await Permission.bluetooth.serviceStatus;
    return status == ServiceStatus.enabled;
  }

  /// Open the app's system settings page (so user can fix denied permissions).
  Future<void> openSettings() => openAppSettings();
}
