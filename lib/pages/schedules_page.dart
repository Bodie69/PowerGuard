import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/device.dart';
import '../models/off_schedule.dart';
import '../services/supabase_service.dart';
import '../widgets/schedule_form_dialog.dart';

class SchedulesPage extends StatelessWidget {
  const SchedulesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final schedules = context.watch<List<OffSchedule>>();
    final devices = context.watch<List<Device>>();
    final device = devices.isEmpty ? null : devices.first;
    final service = context.read<SupabaseService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Schedules'),
      ),
      body: schedules.isEmpty
          ? Center(
              child: Text(
                'No schedules yet. Tap + to add one.',
                style: TextStyle(color: Colors.grey[600]),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: schedules.length,
              itemBuilder: (context, index) {
                final schedule = schedules[index];
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: ListTile(
                    title: Text(
                      'Channel ${schedule.channel} · ${schedule.formattedTime}',
                    ),
                    subtitle: Text(schedule.days.join(', ')),
                    leading: Switch(
                      value: schedule.enabled,
                      onChanged: (value) => service.updateSchedule(
                        id: schedule.id,
                        enabled: value,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () async {
                            final result = await showScheduleFormDialog(
                              context,
                              existing: schedule,
                            );
                            if (result != null) {
                              await service.updateSchedule(
                                id: schedule.id,
                                days: result.days,
                                offTime: _formatTime(result.offTime),
                                enabled: result.enabled,
                              );
                            }
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => service.deleteSchedule(schedule.id),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: device == null
            ? null
            : () async {
                final result = await showScheduleFormDialog(context);
                if (result != null) {
                  await service.createSchedule(
                    deviceId: device.id,
                    channel: result.channel,
                    days: result.days,
                    offTime: _formatTime(result.offTime),
                    enabled: result.enabled,
                  );
                }
              },
        child: const Icon(Icons.add),
      ),
    );
  }

  static String _formatTime(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute:00';
  }
}
