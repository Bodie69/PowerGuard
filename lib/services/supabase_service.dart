import 'dart:async';
import 'dart:developer' as developer;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/channel_history_entry.dart';
import '../models/channel_monthly_energy.dart';
import '../models/channel_reading.dart';
import '../models/device.dart';
import '../models/off_log.dart';
import '../models/off_schedule.dart';
import '../utils/error_mapper.dart';

/// Thin wrapper around the Supabase client: realtime streams for the admin
/// app's read-only views, and mutation methods for the writes an admin is
/// allowed to make (off commands, schedule CRUD, auth).
class SupabaseService {
  SupabaseService(this._client);

  final SupabaseClient _client;

  SupabaseClient get client => _client;

  // ---------------------------------------------------------------------
  // Auth
  // ---------------------------------------------------------------------

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  User? get currentUser => _client.auth.currentUser;

  bool get isAuthenticated => _client.auth.currentSession != null;

  Future<void> signIn({required String email, required String password}) async {
    try {
      await _client.auth.signInWithPassword(email: email, password: password);
    } catch (e, stack) {
      developer.log('SignIn failed: ${ErrorMapper.map(e)}', error: e, stackTrace: stack);
      rethrow;
    }
  }

  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } catch (e, stack) {
      developer.log('SignOut failed: ${ErrorMapper.map(e)}', error: e, stackTrace: stack);
    }
  }

  // ---------------------------------------------------------------------
  // Realtime reads
  // ---------------------------------------------------------------------

  /// Single-device app for now: callers take the first row.
  Stream<List<Device>> devicesStream() {
    return _client
        .from('devices')
        .stream(primaryKey: ['id'])
        .handleError((e) => developer.log('devicesStream error: ${ErrorMapper.map(e)}', error: e))
        .map((rows) => rows.map(Device.fromMap).toList());
  }

  Stream<List<ChannelReading>> channelsStream() {
    return _client
        .from('channels')
        .stream(primaryKey: ['id'])
        .order('channel_number')
        .handleError((e) => developer.log('channelsStream error: ${ErrorMapper.map(e)}', error: e))
        .map((rows) => rows.map(ChannelReading.fromMap).toList());
  }

  /// Live trend for one channel, newest-first from the DB then reversed so
  /// callers get it oldest-first (chart order). Single-device app for now,
  /// same assumption channelsStream()/off_logs already make -- and realtime
  /// postgres_changes filters only support one column anyway, so this can't
  /// also filter by device_id.
  Stream<List<ChannelHistoryEntry>> channelHistoryStream(
    int channelNumber, {
    int limit = 100,
  }) {
    return _client
        .from('channel_history')
        .stream(primaryKey: ['id'])
        .eq('channel_number', channelNumber)
        .order('recorded_at', ascending: false)
        .limit(limit)
        .handleError((e) =>
            developer.log('channelHistoryStream error: ${ErrorMapper.map(e)}', error: e))
        .map((rows) => rows.reversed.map(ChannelHistoryEntry.fromMap).toList());
  }

  /// One-off lookup of the earliest `energy` reading recorded so far this
  /// calendar month (UTC), i.e. the baseline `energy` was at when the month
  /// started. Callers combine this with the latest live reading from
  /// [channelHistoryStream] to get a live-updating monthly total (`energy`
  /// is the PZEM's own cumulative kWh register) without re-querying on
  /// every tick. Returns null if there's no reading yet this month.
  Future<double?> monthStartEnergy(int channelNumber) async {
    final now = DateTime.now().toUtc();
    final monthStart = DateTime.utc(now.year, now.month, 1);
    try {
      final row = await _client
          .from('channel_history')
          .select('energy')
          .eq('channel_number', channelNumber)
          .gte('recorded_at', monthStart.toIso8601String())
          // Skip rows recorded while the meter wasn't answering (energy and
          // voltage both 0): as a baseline they'd make the whole register
          // value look like this month's consumption.
          .or('voltage.gt.0,energy.gt.0')
          .order('recorded_at')
          .limit(1)
          .maybeSingle();
      if (row == null) return null;
      return (row['energy'] as num).toDouble();
    } catch (e, stack) {
      developer.log('monthStartEnergy failed: ${ErrorMapper.map(e)}', error: e, stackTrace: stack);
      return null;
    }
  }

  /// Past months' consumption, archived by the `archive-monthly-energy` cron
  /// job (see supabase/migrations) once each month completes -- unlike
  /// [channelHistoryStream], this survives channel_history's 3-month
  /// retention pruning, so it's the source for anything beyond the current
  /// month.
  Stream<List<ChannelMonthlyEnergy>> monthlyEnergyStream(
    int channelNumber, {
    int limit = 12,
  }) {
    return _client
        .from('channel_monthly_energy')
        .stream(primaryKey: ['id'])
        .eq('channel_number', channelNumber)
        .order('month', ascending: false)
        .limit(limit)
        .handleError((e) =>
            developer.log('monthlyEnergyStream error: ${ErrorMapper.map(e)}', error: e))
        .map((rows) => rows.map(ChannelMonthlyEnergy.fromMap).toList());
  }

  Stream<List<OffSchedule>> schedulesStream() {
    return _client
        .from('off_schedules')
        .stream(primaryKey: ['id'])
        .order('channel')
        .handleError((e) => developer.log('schedulesStream error: ${ErrorMapper.map(e)}', error: e))
        .map((rows) => rows.map(OffSchedule.fromMap).toList());
  }

  Stream<List<OffLog>> offLogsStream() {
    return _client
        .from('off_logs')
        .stream(primaryKey: ['id'])
        .order('timestamp', ascending: false)
        .limit(200)
        .handleError((e) => developer.log('offLogsStream error: ${ErrorMapper.map(e)}', error: e))
        .map((rows) => rows.map(OffLog.fromMap).toList());
  }

  // ---------------------------------------------------------------------
  // Mutations
  // ---------------------------------------------------------------------

  Future<void> sendOffCommand({
    required String deviceId,
    required int channel,
  }) async {
    try {
      await _client.from('off_commands').insert({
        'device_id': deviceId,
        'channel': channel,
        'command': 'OFF',
        'requested_by': currentUser?.id,
      });
    } catch (e, stack) {
      developer.log('sendOffCommand failed: ${ErrorMapper.map(e)}', error: e, stackTrace: stack);
      rethrow;
    }
  }

  Future<void> createSchedule({
    required String deviceId,
    required int channel,
    required List<String> days,
    required String offTime,
    required bool enabled,
  }) async {
    try {
      await _client.from('off_schedules').insert({
        'device_id': deviceId,
        'channel': channel,
        'days': days,
        'off_time': offTime,
        'enabled': enabled,
      });
    } catch (e, stack) {
      developer.log('createSchedule failed: ${ErrorMapper.map(e)}', error: e, stackTrace: stack);
      rethrow;
    }
  }

  Future<void> updateSchedule({
    required String id,
    List<String>? days,
    String? offTime,
    bool? enabled,
  }) async {
    try {
      final updates = <String, dynamic>{};
      if (days != null) updates['days'] = days;
      if (offTime != null) updates['off_time'] = offTime;
      if (enabled != null) updates['enabled'] = enabled;
      if (updates.isEmpty) return;
      await _client.from('off_schedules').update(updates).eq('id', id);
    } catch (e, stack) {
      developer.log('updateSchedule failed: ${ErrorMapper.map(e)}', error: e, stackTrace: stack);
      rethrow;
    }
  }

  Future<void> deleteSchedule(String id) async {
    try {
      await _client.from('off_schedules').delete().eq('id', id);
    } catch (e, stack) {
      developer.log('deleteSchedule failed: ${ErrorMapper.map(e)}', error: e, stackTrace: stack);
      rethrow;
    }
  }
}
