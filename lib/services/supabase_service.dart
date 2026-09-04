import 'dart:async';
import 'dart:developer' as developer;
import 'package:supabase_flutter/supabase_flutter.dart';

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
