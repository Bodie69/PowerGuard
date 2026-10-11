class Device {
  final String id;
  final String deviceName;
  final String status;
  final DateTime? lastSeen;
  final String? firmwareVersion;

  const Device({
    required this.id,
    required this.deviceName,
    required this.status,
    this.lastSeen,
    this.firmwareVersion,
  });

  /// The ESP32 only ever writes status: "online" (on boot and on each
  /// heartbeat) -- it has no way to mark itself offline when it drops off
  /// the network. So "online" is only trustworthy if a heartbeat also
  /// landed recently. The firmware's cloud task sends one every
  /// kHeartbeatMs (10s, esp32_firmware/include/config.h); 35s allows a few
  /// slow or retried requests before calling the device offline. Keep
  /// kHeartbeatMs well under this. Matches the server-side pg_cron job in
  /// supabase/migrations/20260907000000_offline_staleness.sql, which also
  /// flips `status` to 'offline' at this threshold so it's enforced even
  /// with no client connected.
  static const _staleAfter = Duration(seconds: 35);

  bool get isOnline {
    if (status != 'online' || lastSeen == null) return false;
    return DateTime.now().difference(lastSeen!) < _staleAfter;
  }

  factory Device.fromMap(Map<String, dynamic> map) {
    return Device(
      id: map['id'] as String,
      deviceName: map['device_name'] as String? ?? 'PowerGuard Device',
      status: map['status'] as String? ?? 'offline',
      lastSeen: map['last_seen'] == null
          ? null
          : DateTime.parse(map['last_seen'] as String),
      firmwareVersion: map['firmware_version'] as String?,
    );
  }
}
