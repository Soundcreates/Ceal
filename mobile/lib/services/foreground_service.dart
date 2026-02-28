/// Foreground Service — keeps the always-on BLE SOS relay alive on Android.
///
/// Uses [flutter_foreground_task] to run a persistent foreground notification
/// ("Safety network active") so Android does not kill the BLE scan process.
/// Starts automatically on app launch and on device boot.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'package:aftermath/core/constants.dart';

class ForegroundService {
  bool _initialised = false;

  // -------------------------------------------------------------------------
  // Initialisation — also auto-starts the service
  // -------------------------------------------------------------------------

  /// Initialise the foreground task configuration and immediately start.
  /// Call once during app startup.
  Future<void> init() async {
    if (_initialised) return;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'sos_relay_service',
        channelName: 'Safety Network Service',
        channelDescription:
            'Keeps BLE scanning active 24/7 for emergency SOS detection.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    _initialised = true;
    debugPrint('[ForegroundService] Initialised.');

    // Always-on: start the service immediately.
    await start();
  }

  // -------------------------------------------------------------------------
  // Start / Stop
  // -------------------------------------------------------------------------

  /// Start the foreground service with a persistent notification.
  Future<void> start() async {
    if (!_initialised) init();

    final running = await FlutterForegroundTask.isRunningService;
    if (running) {
      debugPrint('[ForegroundService] Already running.');
      return;
    }

    await FlutterForegroundTask.startService(
      notificationTitle: 'Safety network active',
      notificationText: kForegroundNotifBody,
      callback: _foregroundCallback,
    );

    debugPrint('[ForegroundService] Started.');
  }

  /// Stop the foreground service.
  Future<void> stop() async {
    await FlutterForegroundTask.stopService();
    debugPrint('[ForegroundService] Stopped.');
  }

  /// Update the notification text (e.g. to show active alert count).
  Future<void> updateNotification({String? title, String? body}) async {
    await FlutterForegroundTask.updateService(
      notificationTitle: title ?? kForegroundNotifTitle,
      notificationText: body ?? kForegroundNotifBody,
    );
  }
}

// ---------------------------------------------------------------------------
// Top-level callback required by flutter_foreground_task
// ---------------------------------------------------------------------------

@pragma('vm:entry-point')
void _foregroundCallback() {
  FlutterForegroundTask.setTaskHandler(_ScanTaskHandler());
}

class _ScanTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('[ForegroundTask] onStart: $timestamp');
    // BLE scanning is managed by BleScannerService in the main isolate.
    // The foreground service simply keeps the process alive.
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Periodic heartbeat — can be used to verify scanner is still running.
    debugPrint('[ForegroundTask] heartbeat: $timestamp');
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    debugPrint('[ForegroundTask] onDestroy: $timestamp');
  }
}
