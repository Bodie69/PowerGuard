import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/device.dart';
import '../theme/app_theme.dart';

/// Small pill showing whether the ESP32 has reported in recently.
///
/// Device.isOnline depends on wall-clock time (how long since lastSeen),
/// not just on new data arriving, so this widget re-checks on a timer --
/// otherwise it would only update on the next Supabase realtime event.
class ConnectionIndicator extends StatefulWidget {
  const ConnectionIndicator({super.key});

  @override
  State<ConnectionIndicator> createState() => _ConnectionIndicatorState();
}

class _ConnectionIndicatorState extends State<ConnectionIndicator> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final devices = context.watch<List<Device>>();
    final device = devices.isEmpty ? null : devices.first;
    final connected = device?.isOnline ?? false;

    final Color color;
    final String label;
    if (device == null) {
      color = AppColors.warning;
      label = 'No device';
    } else if (connected) {
      color = AppColors.success;
      label = 'Connected';
    } else {
      color = AppColors.danger;
      label = 'Disconnected';
    }

    return Tooltip(
      message: device?.lastSeen == null
          ? 'No data received yet'
          : 'Last seen ${_relativeTime(device!.lastSeen!)}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _relativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
