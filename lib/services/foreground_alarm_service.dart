import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'overcurrent_background_task.dart';

/// Main-isolate facade for the overcurrent-monitoring foreground service.
/// The actual reading/threshold logic lives in [OvercurrentTaskHandler],
/// which runs in a separate isolate spawned by flutter_foreground_task so
/// the watch survives the app being backgrounded or swiped away.
class ForegroundAlarmService {
  ForegroundAlarmService._();

  static bool _initialized = false;

  static void _ensureInitialized() {
    if (_initialized) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'overcurrent_monitor',
        channelName: 'Circuit Monitoring',
        channelDescription:
            'Keeps watching your circuits for overcurrent while the app '
            'is in the background.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    _initialized = true;
  }

  static Future<void> requestPermissions() async {
    final permission =
        await FlutterForegroundTask.checkNotificationPermission();
    if (permission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
  }

  static Future<void> start() async {
    if (!Platform.isAndroid) return;
    _ensureInitialized();
    await requestPermissions();
    if (await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.startService(
      serviceId: 501,
      notificationTitle: 'PowerGuard IoT',
      notificationText: 'Monitoring your circuits for overcurrent.',
      callback: overcurrentTaskCallback,
    );
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid) return;
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }
}
