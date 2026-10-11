import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

enum AppAlertLevel { info, warning, danger }

class AppAlert {
  final String message;
  final AppAlertLevel level;

  const AppAlert(this.message, this.level);
}

/// Listens for off_logs inserts and devices.status flips via Supabase
/// Realtime and emits in-app alerts (shown as SnackBars/banners). This is
/// intentionally not a push-notification service: alerts only fire while
/// the app is open and subscribed.
class RealtimeAlertService {
  RealtimeAlertService(this._client) {
    _subscribe();
  }

  final SupabaseClient _client;
  final _controller = StreamController<AppAlert>.broadcast();
  RealtimeChannel? _channel;

  Stream<AppAlert> get alerts => _controller.stream;

  void _subscribe() {
    _channel = _client
        .channel('powerguard-alerts')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'off_logs',
          callback: (payload) {
            final row = payload.newRecord;
            final channel = row['channel'];
            final reason = row['reason'] as String? ?? 'Off';
            _controller.add(
              AppAlert(
                'Computer $channel turned off: $reason',
                reason == 'Overcurrent'
                    ? AppAlertLevel.danger
                    : AppAlertLevel.warning,
              ),
            );
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'devices',
          callback: (payload) {
            final oldStatus = payload.oldRecord['status'];
            final newStatus = payload.newRecord['status'];
            if (oldStatus == newStatus) return;
            final name = payload.newRecord['device_name'] as String? ??
                'PowerGuard device';
            final isOnline = newStatus == 'online';
            _controller.add(
              AppAlert(
                isOnline ? '$name connected' : '$name disconnected',
                isOnline ? AppAlertLevel.info : AppAlertLevel.warning,
              ),
            );
          },
        )
        .subscribe();
  }

  void dispose() {
    _channel?.unsubscribe();
    _controller.close();
  }
}
