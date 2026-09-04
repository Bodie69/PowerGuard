import 'package:flutter/material.dart';

import '../models/off_schedule.dart';

const kWeekdays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

class ScheduleFormResult {
  final int channel;
  final List<String> days;
  final TimeOfDay offTime;
  final bool enabled;

  const ScheduleFormResult({
    required this.channel,
    required this.days,
    required this.offTime,
    required this.enabled,
  });
}

Future<ScheduleFormResult?> showScheduleFormDialog(
  BuildContext context, {
  OffSchedule? existing,
}) {
  return showDialog<ScheduleFormResult>(
    context: context,
    builder: (context) => _ScheduleFormDialog(existing: existing),
  );
}

class _ScheduleFormDialog extends StatefulWidget {
  const _ScheduleFormDialog({this.existing});

  final OffSchedule? existing;

  @override
  State<_ScheduleFormDialog> createState() => _ScheduleFormDialogState();
}

class _ScheduleFormDialogState extends State<_ScheduleFormDialog> {
  late int _channel = widget.existing?.channel ?? 1;
  late final Set<String> _days = {
    ...(widget.existing?.days ?? const ['MON']),
  };
  late TimeOfDay _time =
      widget.existing?.offTime ?? const TimeOfDay(hour: 18, minute: 0);
  late bool _enabled = widget.existing?.enabled ?? true;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.existing == null ? 'New Schedule' : 'Edit Schedule',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Channel'),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 1, label: Text('1')),
                ButtonSegment(value: 2, label: Text('2')),
                ButtonSegment(value: 3, label: Text('3')),
                ButtonSegment(value: 4, label: Text('4')),
              ],
              selected: {_channel},
              onSelectionChanged: (selection) =>
                  setState(() => _channel = selection.first),
            ),
            const SizedBox(height: 16),
            const Text('Days'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: kWeekdays
                  .map(
                    (day) => FilterChip(
                      label: Text(day),
                      selected: _days.contains(day),
                      onSelected: (selected) => setState(() {
                        if (selected) {
                          _days.add(day);
                        } else {
                          _days.remove(day);
                        }
                      }),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 16),
            const Text('Off Time'),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: _time,
                );
                if (picked != null) {
                  setState(() => _time = picked);
                }
              },
              child: Text(_time.format(context)),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Enabled'),
              value: _enabled,
              onChanged: (value) => setState(() => _enabled = value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _days.isEmpty
              ? null
              : () => Navigator.of(context).pop(
                  ScheduleFormResult(
                    channel: _channel,
                    days: _days.toList(),
                    offTime: _time,
                    enabled: _enabled,
                  ),
                ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
