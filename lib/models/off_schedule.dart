import 'package:flutter/material.dart';

class OffSchedule {
  final String id;
  final String deviceId;
  final int channel;
  final List<String> days;
  final TimeOfDay offTime;
  final bool enabled;

  const OffSchedule({
    required this.id,
    required this.deviceId,
    required this.channel,
    required this.days,
    required this.offTime,
    required this.enabled,
  });

  factory OffSchedule.fromMap(Map<String, dynamic> map) {
    final timeParts = (map['off_time'] as String).split(':');
    return OffSchedule(
      id: map['id'] as String,
      deviceId: map['device_id'] as String,
      channel: map['channel'] as int,
      days: List<String>.from(map['days'] as List? ?? const []),
      offTime: TimeOfDay(
        hour: int.parse(timeParts[0]),
        minute: int.parse(timeParts[1]),
      ),
      enabled: map['enabled'] as bool? ?? true,
    );
  }

  String get formattedTime {
    final hour = offTime.hour.toString().padLeft(2, '0');
    final minute = offTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
