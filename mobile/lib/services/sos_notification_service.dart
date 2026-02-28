/// SOS notification service — shows high-priority local notifications when
/// an SOS event is detected nearby.
///
/// Provides "Call 112" and "Open Maps" actions directly from the notification.
/// Tapping the notification body opens the app and emits via [onNotificationTap]
/// so the UI layer can show a full-screen victim-detail popup.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:aftermath/services/backend_service.dart';
import 'package:aftermath/services/pending_events_db.dart';
import 'package:aftermath/models/sos_type.dart';

class SosNotificationService {
  SosNotificationService();

  /// Stream that fires every time the user taps the notification body.
  /// The emitted map is the full JSON payload (victim details + location + rssi).
  final StreamController<Map<String, dynamic>> _tapController =
      StreamController<Map<String, dynamic>>.broadcast();

  /// Subscribe to this in the UI layer to show the victim-detail popup.
  Stream<Map<String, dynamic>> get onNotificationTap => _tapController.stream;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialised = false;

  // ---------------------------------------------------------------------------
  // Initialisation
  // ---------------------------------------------------------------------------

  Future<void> init() async {
    if (_initialised) return;

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // Create Android notification channel for SOS alerts.
    if (Platform.isAndroid) {
      const channel = AndroidNotificationChannel(
        'sos_alerts',
        'SOS Alerts',
        description: 'High-priority notifications for nearby SOS emergencies.',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );

      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);
    }

    _initialised = true;
    debugPrint('[SosNotificationService] Initialised.');
  }

  // ---------------------------------------------------------------------------
  // Show SOS detection notification
  // ---------------------------------------------------------------------------

  /// Show a high-priority notification for a detected SOS event.
  ///
  /// If [victimProfile] is provided, the notification includes the victim's
  /// name, emergency contacts, blood group, allergies, and conditions.
  /// [rssi] is the raw BLE signal strength and is used for distance estimation.
  Future<void> showSosDetected(
    PendingEvent event, {
    double? distanceMetres,
    VictimProfile? victimProfile,
    int? rssi,
  }) async {
    if (!_initialised) await init();

    final distStr = distanceMetres != null
        ? ' (~${distanceMetres.round()}m away)'
        : '';

    const androidDetails = AndroidNotificationDetails(
      'sos_alerts',
      'SOS Alerts',
      channelDescription:
          'High-priority notifications for nearby SOS emergencies.',
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.alarm,
      fullScreenIntent: true,
      ongoing: false,
      autoCancel: true,
      playSound: true,
      enableVibration: true,
      styleInformation: BigTextStyleInformation(''),
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          'call_112',
          'Call 112',
          showsUserInterface: true,
        ),
        AndroidNotificationAction(
          'open_maps',
          'Open Maps',
          showsUserInterface: true,
        ),
      ],
    );

    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    // ---------- Build rich notification body ----------
    final buf = StringBuffer();

    if (victimProfile != null && victimProfile.name != null) {
      buf.writeln('VICTIM: ${victimProfile.name}');
    } else {
      buf.writeln('UID: ${event.uid}');
    }

    if (victimProfile?.phone != null) {
      buf.writeln('Phone: ${victimProfile!.phone}');
    }

    // RSSI distance estimate in the notification itself.
    if (rssi != null) {
      buf.writeln(
        'Proximity: ${_rssiToDistance(rssi)} (${_rssiLabel(rssi)}, $rssi dBm)',
      );
    }

    if (victimProfile?.medical != null) {
      final med = victimProfile!.medical!;
      if (med.bloodGroup != null && med.bloodGroup!.isNotEmpty) {
        buf.writeln('Blood Group: ${med.bloodGroup}');
      }
      if (med.allergies != null && med.allergies!.isNotEmpty) {
        buf.writeln('Allergies: ${med.allergies}');
      }
      if (med.conditions != null && med.conditions!.isNotEmpty) {
        buf.writeln('Conditions: ${med.conditions}');
      }
    }

    if (victimProfile != null && victimProfile.contacts.isNotEmpty) {
      final contactNames = victimProfile.contacts
          .where((c) => c.name != null && c.name!.isNotEmpty)
          .map((c) => '${c.name} (${c.phone ?? '?'})')
          .join(', ');
      if (contactNames.isNotEmpty) {
        buf.writeln('Emergency Contacts: $contactNames');
      }
    }

    buf.write(
      'Location: ${event.receiverLat.toStringAsFixed(5)}, '
      '${event.receiverLon.toStringAsFixed(5)}$distStr',
    );
    buf.writeln();
    buf.write(
      'Time: ${DateTime.fromMillisecondsSinceEpoch(event.timestamp, isUtc: true).toLocal()}',
    );

    // Determine SOS type from flags.
    final sosType = SosType.fromFlags(event.flags);

    final title = victimProfile?.name != null
        ? '${sosType.label.toUpperCase()} — ${victimProfile!.name}'
        : '${sosType.label.toUpperCase()} DETECTED';

    // ---------- Build JSON payload for tap handler ----------
    final payloadMap = <String, dynamic>{
      'eventId': event.id,
      'uid': event.uid,
      'lat': event.receiverLat,
      'lon': event.receiverLon,
      'rssi': rssi ?? event.rssi,
      'sosType': sosType.name,
      'sosTypeLabel': sosType.label,
      'timestamp': DateTime.fromMillisecondsSinceEpoch(
        event.timestamp,
        isUtc: true,
      ).toIso8601String(),
      if (victimProfile != null) ...{
        'victimName': victimProfile.name,
        'victimPhone': victimProfile.phone,
        'bloodGroup': victimProfile.medical?.bloodGroup,
        'allergies': victimProfile.medical?.allergies,
        'conditions': victimProfile.medical?.conditions,
        'contacts': victimProfile.contacts
            .map((c) => {'name': c.name ?? '', 'phone': c.phone ?? ''})
            .toList(),
      },
    };
    final payloadJson = jsonEncode(payloadMap);

    // Use a unique id per event (hash of id string).
    final notifId = event.id.hashCode.abs() % 0x7FFFFFFF;

    await _plugin.show(
      notifId,
      title,
      buf.toString(),
      details,
      payload: payloadJson,
    );

    debugPrint(
      '[SosNotificationService] Showed notification for ${event.id} '
      '(victim=${victimProfile?.name ?? 'unknown'})',
    );
  }

  // ---------------------------------------------------------------------------
  // Notification tap handler
  // ---------------------------------------------------------------------------

  void _onNotificationTap(NotificationResponse response) {
    final actionId = response.actionId;
    final payload = response.payload;
    debugPrint(
      '[SosNotificationService] Notification tapped: action=$actionId payload=${payload != null ? payload.substring(0, payload.length.clamp(0, 120)) : 'null'}',
    );

    // Parse JSON payload (new format).
    Map<String, dynamic>? data;
    if (payload != null && payload.startsWith('{')) {
      try {
        data = jsonDecode(payload) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('[SosNotificationService] Failed to parse payload JSON: $e');
      }
    }

    // Extract lat/lon for map actions.
    final lat = data?['lat']?.toString();
    final lon = data?['lon']?.toString();

    if (actionId == 'call_112') {
      launchUrl(Uri.parse('tel:112'), mode: LaunchMode.externalApplication);
      return;
    }

    if (actionId == 'open_maps' && lat != null && lon != null) {
      launchUrl(
        Uri.parse('https://maps.google.com/?q=$lat,$lon'),
        mode: LaunchMode.externalApplication,
      );
      return;
    }

    // Tapping notification body → emit event so the app shows the victim popup.
    if (actionId == null || actionId.isEmpty) {
      if (data != null) {
        debugPrint(
          '[SosNotificationService] Emitting tap event for in-app popup',
        );
        _tapController.add(data);
      } else if (lat != null && lon != null) {
        // Fallback: old-format payload, just open maps.
        launchUrl(
          Uri.parse('https://maps.google.com/?q=$lat,$lon'),
          mode: LaunchMode.externalApplication,
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // RSSI → human-readable distance
  // ---------------------------------------------------------------------------

  static String _rssiToDistance(int rssi) {
    const txPower = -59; // dBm at 1m (BLE default)
    const n = 2.7; // indoor path-loss exponent
    final d = math.pow(10, (txPower - rssi) / (10 * n)).toDouble();
    if (d < 1) return '< 1 m';
    if (d < 10) return '~${d.toStringAsFixed(1)} m';
    if (d < 1000) return '~${d.round()} m';
    return '~${(d / 1000).toStringAsFixed(1)} km';
  }

  static String _rssiLabel(int rssi) {
    if (rssi >= -50) return 'Very Strong';
    if (rssi >= -65) return 'Strong';
    if (rssi >= -80) return 'Moderate';
    if (rssi >= -90) return 'Weak';
    return 'Very Weak';
  }

  // ---------------------------------------------------------------------------
  // Dispose
  // ---------------------------------------------------------------------------

  Future<void> dispose() async {
    await _tapController.close();
  }
}
