class ChannelMonthlyEnergy {
  final String id;
  final String deviceId;
  final int channelNumber;
  final DateTime month;
  final double startEnergy;
  final double endEnergy;
  final double consumedKwh;

  const ChannelMonthlyEnergy({
    required this.id,
    required this.deviceId,
    required this.channelNumber,
    required this.month,
    required this.startEnergy,
    required this.endEnergy,
    required this.consumedKwh,
  });

  factory ChannelMonthlyEnergy.fromMap(Map<String, dynamic> map) {
    double asDouble(dynamic value) =>
        value == null ? 0.0 : (value as num).toDouble();

    return ChannelMonthlyEnergy(
      id: map['id'] as String,
      deviceId: map['device_id'] as String,
      channelNumber: map['channel_number'] as int,
      month: DateTime.parse(map['month'] as String),
      startEnergy: asDouble(map['start_energy']),
      endEnergy: asDouble(map['end_energy']),
      consumedKwh: asDouble(map['consumed_kwh']),
    );
  }
}
