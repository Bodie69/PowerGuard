import '../models/device.dart';

/// Smooths transient offline flips in the UI. `devices.status` briefly goes
/// 'offline' whenever a single slow HTTP call in runCloudSync() delays the
/// firmware's heartbeat past the server-side staleness threshold (see
/// supabase/migrations/20260907000000_offline_staleness.sql) even though the
/// device never actually lost WiFi -- and that flip is pushed to every
/// listener over Realtime, not just recomputed locally, so it can't be
/// filtered by widening the threshold alone.
///
/// Coming back online is shown immediately (a fresh reading is unambiguous
/// good news). Going offline must hold continuously for [confirmDelay]
/// before it's shown, so a one-tick blip that recovers on the next
/// heartbeat never reaches the screen.
class DeviceOnlineDebouncer {
  DeviceOnlineDebouncer({this.confirmDelay = const Duration(seconds: 6)});

  final Duration confirmDelay;
  bool _displayed = true;
  DateTime? _offlineSince;

  bool update(Device? device) {
    final raw = device?.isOnline ?? false;
    if (raw) {
      _offlineSince = null;
      _displayed = true;
    } else {
      final since = _offlineSince ??= DateTime.now();
      if (DateTime.now().difference(since) >= confirmDelay) {
        _displayed = false;
      }
    }
    return _displayed;
  }
}
