import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../models/channel_reading.dart';
import 'notification_service.dart';

const double kOvercurrentThresholdA = 1.0;

/// Entry point for the foreground-service isolate. Must stay top-level (or
/// static) and annotated `vm:entry-point` -- flutter_foreground_task spawns a
/// separate isolate for this that shares no memory with the main isolate, so
/// it gets its own Supabase client and notification-plugin instance below.
/// The binding must be initialized here (nothing does it automatically in
/// this isolate) before any plugin channel -- including AudioPlayer's own
/// constructor -- is touched.
@pragma('vm:entry-point')
void overcurrentTaskCallback() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.setTaskHandler(OvercurrentTaskHandler());
}

/// Watches the live channels table for a current draw above
/// [kOvercurrentThresholdA] (matching the ESP32 firmware's own
/// `kCurrentLimitA` cutoff) and raises a system notification + looped alarm
/// sound. Runs inside the foreground service so the watch survives the app
/// being backgrounded or swiped away.
class OvercurrentTaskHandler extends TaskHandler {
  StreamSubscription<List<Map<String, dynamic>>>? _subscription;
  final AudioPlayer _player = AudioPlayer();
  final Set<int> _breachedChannels = {};
  int? _lastTriggeredChannel;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await dotenv.load(fileName: '.env');
    // This isolate shares no memory with the main isolate, so Supabase.init
    // (a no-op if this isolate already ran it) needs to happen again here.
    await Supabase.initialize(
      url: Config.supabaseUrl,
      publishableKey: Config.supabaseAnonKey,
    );
    await NotificationService.instance.init();

    _subscription = Supabase.instance.client
        .from('channels')
        .stream(primaryKey: ['id'])
        .order('channel_number')
        .listen(_onRows, onError: (_) {});
  }

  void _onRows(List<Map<String, dynamic>> rows) {
    final readings = rows.map(ChannelReading.fromMap).toList();
    final breachedNow = readings
        .where((r) => r.current > kOvercurrentThresholdA)
        .map((r) => r.channelNumber)
        .toSet();
    // Evaluated eagerly before _breachedChannels is mutated below, since
    // readings.where(...) is otherwise a lazy Iterable -- see the identical
    // bug (and fix) in the in-app alarm controller this replaced.
    final newlyBreached = readings
        .where(
          (r) => breachedNow.contains(r.channelNumber) &&
              !_breachedChannels.contains(r.channelNumber),
        )
        .toList();

    _breachedChannels
      ..clear()
      ..addAll(breachedNow);

    if (breachedNow.isEmpty) {
      _player.stop();
      return;
    }

    if (newlyBreached.isEmpty) return;

    _trigger(newlyBreached.first);
  }

  void _trigger(ChannelReading reading) {
    _lastTriggeredChannel = reading.channelNumber;
    _playAlarm();
    NotificationService.instance.showOvercurrentAlert(
      channel: reading.channelNumber,
      current: reading.current,
    );
    FlutterForegroundTask.sendDataToMain({
      'event': 'overcurrent',
      'channel': reading.channelNumber,
      'current': reading.current,
    });
  }

  Future<void> _playAlarm() async {
    try {
      await _player.stop();
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.play(AssetSource('sounds/navy_overpressure_al.mp3'));
    } catch (_) {
      // Best-effort: a missing/unsupported audio backend shouldn't block
      // the notification above.
    }
  }

  @override
  void onReceiveData(Object data) {
    if (data is! Map) return;
    // Sent by the UI when the user taps "Acknowledge" on the in-app dialog,
    // so the alarm stops immediately rather than waiting for the next
    // below-threshold reading.
    if (data['ack'] == true) {
      _player.stop();
      final channel = _lastTriggeredChannel;
      if (channel != null) {
        NotificationService.instance.cancelOvercurrentAlert(channel);
      }
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    await _subscription?.cancel();
    await _player.stop();
    await _player.dispose();
  }
}
