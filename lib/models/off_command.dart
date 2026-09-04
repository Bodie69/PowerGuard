class OffCommand {
  final String id;
  final String deviceId;
  final int channel;
  final String command;
  final String status;
  final String? requestedBy;
  final DateTime createdAt;
  final DateTime? processedAt;

  const OffCommand({
    required this.id,
    required this.deviceId,
    required this.channel,
    required this.command,
    required this.status,
    this.requestedBy,
    required this.createdAt,
    this.processedAt,
  });

  factory OffCommand.fromMap(Map<String, dynamic> map) {
    return OffCommand(
      id: map['id'] as String,
      deviceId: map['device_id'] as String,
      channel: map['channel'] as int,
      command: map['command'] as String? ?? 'OFF',
      status: map['status'] as String? ?? 'pending',
      requestedBy: map['requested_by'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      processedAt: map['processed_at'] == null
          ? null
          : DateTime.parse(map['processed_at'] as String),
    );
  }
}
