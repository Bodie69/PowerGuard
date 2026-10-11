import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/channel_reading.dart';
import '../models/device.dart';
import '../services/dashboard_layout_controller.dart';
import '../services/device_online_debouncer.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/channel_card.dart';
import '../widgets/connection_indicator.dart';
import '../widgets/dashboard_customize_sheet.dart';
import 'channel_details_page.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final rawChannels = context.watch<List<ChannelReading>>();
    final devices = context.watch<List<Device>>();
    final device = devices.isEmpty ? null : devices.first;
    final layout = context.watch<DashboardLayoutController>();

    void showDetails(ChannelReading reading) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              ChannelDetailsPage(channelNumber: reading.channelNumber),
        ),
      );
    }

    Future<void> turnOff(ChannelReading reading) async {
      if (device == null) return;
      final service = context.read<SupabaseService>();
      try {
        await service.sendOffCommand(
          deviceId: device.id,
          channel: reading.channelNumber,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Off command sent for channel ${reading.channelNumber}',
              ),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to send off command. Check connection.'),
              backgroundColor: AppColors.danger,
            ),
          );
        }
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: Center(child: ConnectionIndicator()),
          ),
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Customize dashboard',
            onPressed: () => showDashboardCustomizeSheet(context),
          ),
        ],
      ),
      body: Column(
        children: [
          _OfflineBanner(device: device),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                // Streams refresh automatically, but we can add a small delay
                // to make the user feel like something happened.
                await Future.delayed(const Duration(seconds: 1));
              },
              child: _ChannelGrid(
                rawChannels: rawChannels,
                device: device,
                layout: layout,
                onOff: turnOff,
                onDetails: showDetails,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Builds the channel cards from live data. Device.isOnline depends on
/// wall-clock time, not just on new readings arriving, so this re-checks on
/// a timer to zero out the meter values once the device goes stale --
/// otherwise a channel would keep showing its last (now meaningless)
/// reading until the next Supabase realtime event, same as ConnectionIndicator.
class _ChannelGrid extends StatefulWidget {
  const _ChannelGrid({
    required this.rawChannels,
    required this.device,
    required this.layout,
    required this.onOff,
    required this.onDetails,
  });

  final List<ChannelReading> rawChannels;
  final Device? device;
  final DashboardLayoutController layout;
  final Future<void> Function(ChannelReading) onOff;
  final void Function(ChannelReading) onDetails;

  @override
  State<_ChannelGrid> createState() => _ChannelGridState();
}

class _ChannelGridState extends State<_ChannelGrid> {
  Timer? _ticker;
  final _onlineDebouncer = DeviceOnlineDebouncer();

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 3), (_) {
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
    final device = widget.device;
    final layout = widget.layout;
    final online = _onlineDebouncer.update(device);

    final List<ChannelReading> channels;
    if (widget.rawChannels.isEmpty) {
      channels = List.generate(4, (i) {
        final channelNum = i + 1;
        return ChannelReading(
          id: 'placeholder-$channelNum',
          deviceId: device?.id ?? 'no-device',
          channelNumber: channelNum,
          voltage: 0.0,
          current: 0.0,
          power: 0.0,
          energy: 0.0,
          frequency: 0.0,
          powerFactor: 1.0,
          breakerStatus: 'OFF',
          updatedAt: DateTime.now(),
        );
      });
    } else {
      final sorted = layout.sortByChannelOrder(
        widget.rawChannels,
        (c) => c.channelNumber,
      );
      // Zero a channel's live meter values whenever the whole device is
      // offline OR that channel's own breaker is OFF -- a computer that's
      // off shouldn't show stale/leftover voltage, current, etc. just
      // because the ESP32 itself is still online.
      channels = sorted
          .map((c) => (!online || c.isOff) ? c.zeroed() : c)
          .toList();
    }

    return _buildLayout(
      context,
      channels,
      layout,
      widget.onOff,
      widget.onDetails,
      online: online,
    );
  }

  Widget _buildLayout(
    BuildContext context,
    List<ChannelReading> channels,
    DashboardLayoutController layout,
    Future<void> Function(ChannelReading) onOff,
    void Function(ChannelReading) onDetails, {
    required bool online,
  }) {
    switch (layout.viewMode) {
      case DashboardViewMode.relative:
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 80, top: 8),
          itemCount: channels.length,
          itemBuilder: (context, index) {
            final reading = channels[index];
            return ChannelCard(
              reading: reading,
              displayMode: layout.getChannelDisplayMode(reading.channelNumber),
              color: layout.getChannelColor(
                reading.channelNumber,
                AppColors.primary,
              ),
              isOnline: online,
              visibleMetrics: layout.visibleMetrics,
              onOff: () => onOff(reading),
              onDetails: () => onDetails(reading),
            );
          },
        );

      case DashboardViewMode.absolute:
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 220,
            mainAxisExtent: 260,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: channels.length,
          itemBuilder: (context, index) {
            final reading = channels[index];
            return ChannelCard(
              reading: reading,
              compact: true,
              displayMode: layout.getChannelDisplayMode(reading.channelNumber),
              color: layout.getChannelColor(
                reading.channelNumber,
                AppColors.primary,
              ),
              isOnline: online,
              visibleMetrics: layout.visibleMetrics,
              onOff: () => onOff(reading),
              onDetails: () => onDetails(reading),
            );
          },
        );

      case DashboardViewMode.stack:
        return Stack(
          children: [
            for (int i = 0; i < channels.length; i++)
              Positioned(
                top: 20.0 + (i * 60.0),
                left: 16.0 + (i * 8.0),
                right: 16.0 - (i * 8.0),
                child: ChannelCard(
                  reading: channels[i],
                  displayMode:
                      layout.getChannelDisplayMode(channels[i].channelNumber),
                  color: layout.getChannelColor(
                    channels[i].channelNumber,
                    AppColors.primary,
                  ),
                  isOnline: online,
                  visibleMetrics: layout.visibleMetrics,
                  onOff: () => onOff(channels[i]),
                  onDetails: () => onDetails(channels[i]),
                ),
              ),
            // Padding at bottom for FAB/etc
            const Positioned(bottom: 0, child: SizedBox(height: 80)),
          ],
        );
    }
  }
}

/// Device.isOnline depends on wall-clock time (how long since lastSeen), not
/// just on new data arriving, so this re-checks on a timer -- otherwise the
/// banner would only update on the next Supabase realtime event, same as
/// ConnectionIndicator. Uses [DeviceOnlineDebouncer] so a transient offline
/// flip doesn't flash the banner on and off.
class _OfflineBanner extends StatefulWidget {
  const _OfflineBanner({required this.device});

  final Device? device;

  @override
  State<_OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<_OfflineBanner> {
  Timer? _ticker;
  final _onlineDebouncer = DeviceOnlineDebouncer();

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 3), (_) {
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
    final device = widget.device;
    if (device == null || _onlineDebouncer.update(device)) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      color: AppColors.warning.withValues(alpha: 0.9),
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      child: const Row(
        children: [
          Icon(Icons.wifi_off, size: 16, color: Colors.white),
          SizedBox(width: 8),
          Text(
            'Device is offline. Data may be stale.',
            style: TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
