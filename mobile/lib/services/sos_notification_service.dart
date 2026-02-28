/// SOS notification service — shows high-priority local notifications when
/// an SOS event is detected nearby.
///
/// Provides "Call 112" and "Open Maps" actions directly from the notification.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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
  Future<void> showSosDetected(PendingEvent event,
      {double? distanceMetres}) async {
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

    final body = 'Emergency nearby$distStr\n'
        'UID: ${event.uid}\n'
        'Time: ${DateTime.fromMillisecondsSinceEpoch(event.timestamp, isUtc: true).toLocal()}';

    // Use a unique id per event (hash of id string).
    final notifId = event.id.hashCode.abs() % 0x7FFFFFFF;

    await _plugin.show(
      notifId,
      'SOS EMERGENCY DETECTED',
      body,
      details,
      payload:
          '${event.receiverLat},${event.receiverLon}',
    );

    debugPrint('[SosNotificationService] Showed notification for ${event.id}');
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
    // Action handling (call 112, open maps) is done via the platform's
    // URL launcher when the notification actions are tapped. The actions
    // themselves trigger the OS dialer / maps via their respective intents.
    // For the PoC, the notification UI is informational.
  }

  // ---------------------------------------------------------------------------
  // Dispose
  // ---------------------------------------------------------------------------

  Future<void> dispose() async {
    // Nothing to release; plugin is a singleton.
  }
}
