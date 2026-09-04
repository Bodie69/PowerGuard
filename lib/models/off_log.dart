class OffLog {
  final String id;
  final String deviceId;
  final int channel;
  final String reason;
  final double voltage;
  final double current;
  final double power;
  final DateTime timestamp;
  final String? triggeredBy;

  const OffLog({
    required this.id,
    required this.deviceId,
    required this.channel,
    required this.reason,
    required this.voltage,
    required this.current,
    required this.power,
    required this.timestamp,
    this.triggeredBy,
  });

  factory OffLog.fromMap(Map<String, dynamic> map) {
    double asDouble(dynamic value) =>
        value == null ? 0.0 : (value as num).toDouble();

    return OffLog(
      id: map['id'] as String,
      deviceId: map['device_id'] as String,
      channel: map['channel'] as int,
      reason: map['reason'] as String,
      voltage: asDouble(map['voltage']),
      current: asDouble(map['current']),
      power: asDouble(map['power']),
      timestamp: DateTime.parse(map['timestamp'] as String),
      triggeredBy: map['triggered_by'] as String?,
    );
  }
}
