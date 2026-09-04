class ChannelReading {
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
  final DateTime updatedAt;

  const ChannelReading({
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
    required this.updatedAt,
  });

  bool get isOff => breakerStatus == 'OFF';

  factory ChannelReading.fromMap(Map<String, dynamic> map) {
    double asDouble(dynamic value) =>
        value == null ? 0.0 : (value as num).toDouble();

    return ChannelReading(
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
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
