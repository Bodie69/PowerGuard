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

  /// Used both when the device has dropped offline (the PZEM stops
  /// reporting the moment the ESP32 drops off the network, so a stale
  /// reading is frozen at whatever it last measured -- showing e.g. "230V,
  /// 5A" while actually disconnected implies power is still flowing) and
  /// when the channel's own breaker is OFF (a raw reading can still show
  /// non-zero values momentarily, e.g. wiring where the PZEM sits upstream
  /// of the relay). Zero every displayed meter value, energy included: a dead
  /// or OFF channel shouldn't keep showing the meter's last register value
  /// (e.g. 0.61 kWh) next to 0 V / 0 A. This is display-only -- the stored
  /// register and channel_history are untouched, and the monthly total is
  /// computed from channel_history, not from this object.
  ChannelReading zeroed() => ChannelReading(
        id: id,
        deviceId: deviceId,
        channelNumber: channelNumber,
        voltage: 0.0,
        current: 0.0,
        power: 0.0,
        energy: 0.0,
        frequency: 0.0,
        powerFactor: 0.0,
        breakerStatus: breakerStatus,
        updatedAt: updatedAt,
      );

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
