class ChannelHistoryEntry {
  final String id;
  final String deviceId;
  final int channelNumber;
  final double voltage;
  final double current;
  final double power;
  final double energy;
  final double frequency;
  final double powerFactor;
  final String breakerStatus;
  final DateTime recordedAt;

  const ChannelHistoryEntry({
    required this.id,
    required this.deviceId,
    required this.channelNumber,
    required this.voltage,
    required this.current,
    required this.power,
    required this.energy,
    required this.frequency,
    required this.powerFactor,
    required this.breakerStatus,
    required this.recordedAt,
  });

  factory ChannelHistoryEntry.fromMap(Map<String, dynamic> map) {
    double asDouble(dynamic value) =>
        value == null ? 0.0 : (value as num).toDouble();

    return ChannelHistoryEntry(
      id: map['id'] as String,
      deviceId: map['device_id'] as String,
      channelNumber: map['channel_number'] as int,
      voltage: asDouble(map['voltage']),
      current: asDouble(map['current']),
      power: asDouble(map['power']),
      energy: asDouble(map['energy']),
      frequency: asDouble(map['frequency']),
      powerFactor: asDouble(map['power_factor']),
      breakerStatus: map['breaker_status'] as String? ?? 'ON',
      recordedAt: DateTime.parse(map['recorded_at'] as String),
    );
  }
}
