/// SOS notification service — shows high-priority local notifications when
/// an SOS event is detected nearby.
///
/// Provides "Call 112" and "Open Maps" actions directly from the notification.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:aftermath/services/backend_service.dart';
import 'package:aftermath/services/pending_events_db.dart';

class SosNotificationService {
  SosNotificationService();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialised = false;

  // ---------------------------------------------------------------------------
  // Initialisation
  // ---------------------------------------------------------------------------

  Future<void> init() async {
    if (_initialised) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
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
              AndroidFlutterLocalNotificationsPlugin>()
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
  Future<void> showSosDetected(
    PendingEvent event, {
    double? distanceMetres,
    VictimProfile? victimProfile,
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

    buf.write('Location: ${event.receiverLat.toStringAsFixed(5)}, '
        '${event.receiverLon.toStringAsFixed(5)}$distStr');
    buf.writeln();
    buf.write(
      'Time: ${DateTime.fromMillisecondsSinceEpoch(event.timestamp, isUtc: true).toLocal()}',
    );

    final title = victimProfile?.name != null
        ? 'SOS EMERGENCY — ${victimProfile!.name}'
        : 'SOS EMERGENCY DETECTED';

    // Use a unique id per event (hash of id string).
    final notifId = event.id.hashCode.abs() % 0x7FFFFFFF;

    await _plugin.show(
      notifId,
      title,
      buf.toString(),
      details,
      payload:
          '${event.receiverLat},${event.receiverLon}',
    );

    debugPrint('[SosNotificationService] Showed notification for ${event.id} '
        '(victim=${victimProfile?.name ?? 'unknown'})');
  }

  // ---------------------------------------------------------------------------
  // Notification tap handler
  // ---------------------------------------------------------------------------

  void _onNotificationTap(NotificationResponse response) {
    final actionId = response.actionId;
    final payload = response.payload;
    debugPrint(
      '[SosNotificationService] Notification tapped: action=$actionId payload=$payload',
    );

    if (actionId == 'call_112') {
      launchUrl(Uri.parse('tel:112'), mode: LaunchMode.externalApplication);
      return;
    }

    if (actionId == 'open_maps' && payload != null && payload.isNotEmpty) {
      final parts = payload.split(',');
      if (parts.length == 2) {
        final lat = parts[0].trim();
        final lon = parts[1].trim();
        // Try Google Maps app first, fall back to browser
        launchUrl(
          Uri.parse('https://maps.google.com/?q=$lat,$lon'),
          mode: LaunchMode.externalApplication,
        );
      }
      return;
    }

    // Tapping the notification body (no action) — also open maps if loc available
    if (actionId == null && payload != null && payload.isNotEmpty) {
      final parts = payload.split(',');
      if (parts.length == 2) {
        launchUrl(
          Uri.parse('https://maps.google.com/?q=${parts[0].trim()},${parts[1].trim()}'),
          mode: LaunchMode.externalApplication,
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Dispose
  // ---------------------------------------------------------------------------

  Future<void> dispose() async {
    // Nothing to release; plugin is a singleton.
  }
}
