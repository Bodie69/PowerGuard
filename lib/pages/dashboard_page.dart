import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/channel_reading.dart';
import '../models/device.dart';
import '../services/dashboard_layout_controller.dart';
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

    final isOffline = device != null && !device.isOnline;

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

    final List<ChannelReading> channels;
    if (rawChannels.isEmpty) {
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
      channels = layout.sortByChannelOrder(
        rawChannels,
        (c) => c.channelNumber,
      );
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
          if (isOffline)
            Container(
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
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                // Streams refresh automatically, but we can add a small delay
                // to make the user feel like something happened.
                await Future.delayed(const Duration(seconds: 1));
              },
              child: _buildLayout(
                  context, channels, layout, turnOff, showDetails),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLayout(
    BuildContext context,
    List<ChannelReading> channels,
    DashboardLayoutController layout,
    Future<void> Function(ChannelReading) onOff,
    void Function(ChannelReading) onDetails,
  ) {
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
