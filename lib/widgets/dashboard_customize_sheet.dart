import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/dashboard_layout_controller.dart';
import '../theme/app_theme.dart';

const _kChannelPresets = [
  AppColors.primary,
  Colors.green,
  Colors.orange,
  Colors.purple,
  Colors.teal,
  Colors.indigo,
];

Future<void> showDashboardCustomizeSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const DashboardCustomizeSheet(),
  );
}

class DashboardCustomizeSheet extends StatelessWidget {
  const DashboardCustomizeSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DashboardLayoutController>();
    final viewInsets = MediaQuery.of(context).viewInsets;

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            children: [
              Text(
                'Customize Dashboard',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 20),
              Text(
                'Layout',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(color: Colors.grey[600]),
              ),
              const SizedBox(height: 8),
              SegmentedButton<DashboardViewMode>(
                segments: const [
                  ButtonSegment(
                    value: DashboardViewMode.relative,
                    label: Text('Relative'),
                    icon: Icon(Icons.view_agenda_outlined),
                  ),
                  ButtonSegment(
                    value: DashboardViewMode.absolute,
                    label: Text('Absolute'),
                    icon: Icon(Icons.grid_view_outlined),
                  ),
                  ButtonSegment(
                    value: DashboardViewMode.stack,
                    label: Text('Stack'),
                    icon: Icon(Icons.layers_outlined),
                  ),
                ],
                selected: {controller.viewMode},
                onSelectionChanged: (selection) =>
                    controller.setViewMode(selection.first),
              ),
              const SizedBox(height: 24),
              Text(
                'Channel order',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(color: Colors.grey[600]),
              ),
              const SizedBox(height: 4),
              Text(
                'Drag to reorder how channels appear on the dashboard.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[500],
                ),
              ),
              const SizedBox(height: 8),
              _ChannelOrderList(controller: controller),
              const SizedBox(height: 24),
              Text(
                'Display Mode',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(color: Colors.grey[600]),
              ),
              const SizedBox(height: 4),
              Text(
                'Switch between Digital (text) and Analog (gauge) views.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[500],
                ),
              ),
              const SizedBox(height: 8),
              _ChannelDisplayModeList(controller: controller),
              const SizedBox(height: 24),
              Text(
                'Visible metrics',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(color: Colors.grey[600]),
              ),
              const SizedBox(height: 4),
              Text(
                'Choose which stats show on each channel card.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[500],
                ),
              ),
              ...kAllChannelMetrics.map((metric) {
                final visible = controller.visibleMetrics.contains(metric);
                final isLastVisible =
                    visible && controller.visibleMetrics.length == 1;
                return CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(kChannelMetricLabels[metric]!),
                  value: visible,
                  onChanged: isLastVisible
                      ? null
                      : (value) =>
                            controller.setMetricVisible(metric, value ?? false),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}

class _ChannelOrderList extends StatelessWidget {
  const _ChannelOrderList({required this.controller});

  final DashboardLayoutController controller;

  @override
  Widget build(BuildContext context) {
    final order = controller.channelOrder;

    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: order.length,
      onReorder: controller.reorderChannel,
      itemBuilder: (context, index) {
        final channel = order[index];
        return Card(
          key: ValueKey('channel-order-$channel'),
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: ListTile(
            leading: const Icon(Icons.drag_indicator),
            title: Text('Channel $channel'),
            trailing: ReorderableDragStartListener(
              index: index,
              child: const Icon(Icons.swap_vert),
            ),
          ),
        );
      },
    );
  }
}

class _ChannelDisplayModeList extends StatelessWidget {
  const _ChannelDisplayModeList({required this.controller});

  final DashboardLayoutController controller;

  @override
  Widget build(BuildContext context) {
    final channels = controller.channelOrder;

    return Column(
      children: channels.map((channel) {
        final mode = controller.getChannelDisplayMode(channel);
        final currentColor = controller.getChannelColor(channel, AppColors.primary);

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Channel $channel'),
                    SegmentedButton<ChannelDisplayMode>(
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                      ),
                      segments: const [
                        ButtonSegment(
                          value: ChannelDisplayMode.digital,
                          label: Text('Digital', style: TextStyle(fontSize: 12)),
                        ),
                        ButtonSegment(
                          value: ChannelDisplayMode.analog,
                          label: Text('Analog', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                      selected: {mode},
                      onSelectionChanged: (selection) =>
                          controller.setChannelDisplayMode(channel, selection.first),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('Color: ', style: TextStyle(fontSize: 12)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: _kChannelPresets.map((color) {
                          final isSelected = currentColor.toARGB32() == color.toARGB32();
                          return GestureDetector(
                            onTap: () => controller.setChannelColor(channel, color),
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: isSelected
                                    ? Border.all(color: Colors.black, width: 2)
                                    : null,
                              ),
                              child: isSelected
                                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                                  : null,
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
