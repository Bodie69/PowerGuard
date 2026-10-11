import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Thin wrapper around `flutter_local_notifications` for the one alert this
/// app needs: a high-priority heads-up notification when a channel exceeds
/// the overcurrent threshold. Used from both the main isolate and the
/// background foreground-service isolate (each needs its own `init()` call,
/// since plugin state isn't shared across isolates).
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const _channelId = 'overcurrent_alerts';
  static const _channelName = 'Overcurrent Alerts';

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      const InitializationSettings(android: androidInit),
    );
    _initialized = true;
  }

  Future<void> showOvercurrentAlert({
    required int channel,
    required double current,
  }) async {
    await init();
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Alerts when a channel draws more than 1A.',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
    );
    await _plugin.show(
      channel,
      'Overcurrent Detected',
      'Computer $channel is drawing ${current.toStringAsFixed(1)} A, '
          'above the 1 A safety limit.',
      const NotificationDetails(android: androidDetails),
    );
  }

  Future<void> cancelOvercurrentAlert(int channel) => _plugin.cancel(channel);
}
