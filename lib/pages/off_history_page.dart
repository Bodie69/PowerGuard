import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/off_log.dart';
import '../theme/app_theme.dart';

class OffHistoryPage extends StatefulWidget {
  const OffHistoryPage({super.key});

  @override
  State<OffHistoryPage> createState() => _OffHistoryPageState();
}

class _OffHistoryPageState extends State<OffHistoryPage> {
  int? _channelFilter;

  @override
  Widget build(BuildContext context) {
    final logs = context.watch<List<OffLog>>();
    final filtered = _channelFilter == null
        ? logs
        : logs.where((log) => log.channel == _channelFilter).toList();
    final dateFormat = DateFormat('MMM d, y · h:mm a');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Off History'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                const Text('Channel:'),
                const SizedBox(width: 8),
                DropdownButton<int?>(
                  value: _channelFilter,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All')),
                    for (final c in [1, 2, 3, 4])
                      DropdownMenuItem(value: c, child: Text('$c')),
                  ],
                  onChanged: (value) => setState(() => _channelFilter = value),
                ),
              ],
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      'No off events yet.',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  )
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final log = filtered[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: _reasonColor(
                              context,
                              log.reason,
                            ).withValues(alpha: 0.15),
                            child: Icon(
                              Icons.power_off,
                              color: _reasonColor(context, log.reason),
                            ),
                          ),
                          title: Text(
                            'Channel ${log.channel} · ${log.reason}',
                          ),
                          subtitle: Text(
                            '${dateFormat.format(log.timestamp.toLocal())}'
                            '${log.triggeredBy != null ? ' · ${log.triggeredBy}' : ''}\n'
                            '${log.voltage.toStringAsFixed(1)} V · '
                            '${log.current.toStringAsFixed(2)} A · '
                            '${log.power.toStringAsFixed(1)} W',
                          ),
                          isThreeLine: true,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Color _reasonColor(BuildContext context, String reason) {
    switch (reason) {
      case 'Overcurrent':
        return AppColors.danger;
      case 'Manual Off':
        return AppColors.warning;
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }
}
