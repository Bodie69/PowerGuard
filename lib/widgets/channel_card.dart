import 'package:flutter/material.dart';

import '../models/channel_reading.dart';
import '../services/dashboard_layout_controller.dart';
import '../theme/app_theme.dart';
import '../theme/design_tokens.dart';
import 'analog_gauge.dart';
import 'elevated_metric_card.dart';
import 'status_chip.dart';
import 'off_confirmation_dialog.dart';

class ChannelCard extends StatelessWidget {
  const ChannelCard({
    super.key,
    required this.reading,
    required this.onOff,
    this.onDetails,
    this.displayMode = ChannelDisplayMode.digital,
    this.compact = false,
    this.color = AppColors.primary,
    this.isOnline = true,
    this.visibleMetrics = const {
      'voltage',
      'current',
      'power',
      'energy',
      'frequency',
      'power_factor',
    },
  });

  final ChannelReading reading;
  final Future<void> Function() onOff;
  final VoidCallback? onDetails;
  final ChannelDisplayMode displayMode;
  final bool compact;
  final Color color;

  /// Whether the device is actually reporting in right now. When false,
  /// [reading.breakerStatus] is stale (frozen at whatever it last reported)
  /// so it can't be trusted as the real status -- show OFFLINE instead.
  final bool isOnline;

  /// Which metric keys (see [kAllChannelMetrics]) to render.
  final Set<String> visibleMetrics;

  @override
  Widget build(BuildContext context) {
    final isOff = reading.isOff;
    final effectiveColor = isOff ? Colors.grey : color;

    final metrics = <String, ElevatedMetricCard>{
      'voltage': ElevatedMetricCard(
        label: 'Voltage',
        value: '${reading.voltage.toStringAsFixed(1)} V',
        color: effectiveColor,
      ),
      'current': ElevatedMetricCard(
        label: 'Current',
        value: '${reading.current.toStringAsFixed(2)} A',
        color: effectiveColor,
      ),
      'power': ElevatedMetricCard(
        label: 'Power',
        value: '${reading.power.toStringAsFixed(1)} W',
        color: effectiveColor,
      ),
      'energy': ElevatedMetricCard(
        label: 'Energy',
        value: '${reading.energy.toStringAsFixed(2)} kWh',
        color: effectiveColor,
      ),
      'frequency': ElevatedMetricCard(
        label: 'Frequency',
        value: '${reading.frequency.toStringAsFixed(1)} Hz',
        color: effectiveColor,
      ),
      'power_factor': ElevatedMetricCard(
        label: 'Power Factor',
        value: reading.powerFactor.toStringAsFixed(2),
        color: effectiveColor,
      ),
    };
    final shownMetrics = [
      for (final key in kAllChannelMetrics)
        if (visibleMetrics.contains(key)) metrics[key]!,
    ];

    final statusLabel = isOnline ? reading.breakerStatus : 'OFFLINE';
    final statusColor = switch (statusLabel) {
      'ON' => AppColors.success,
      'OFF' => AppColors.danger,
      'OFFLINE' => AppColors.danger,
      _ => Colors.grey,
    };

    return Card(
      child: InkWell(
        onTap: onDetails,
        borderRadius: BorderRadius.circular(DesignTokens.radiusMedium),
        child: Padding(
          padding: EdgeInsets.all(
            compact ? DesignTokens.spacingSmall : DesignTokens.spacingMedium
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Computer ${reading.channelNumber}',
                        style: compact
                            ? Theme.of(context).textTheme.titleSmall
                            : Theme.of(context).textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (!compact)
                      StatusChip(
                        label: statusLabel,
                        color: statusColor,
                      ),
                  ],
                ),
                SizedBox(
                  height: compact ? DesignTokens.spacingXSmall : DesignTokens.spacingSmall
                ),
                if (displayMode == ChannelDisplayMode.analog) ...[
                  SizedBox(
                    height: compact ? 140 : 220,
                    child: Center(
                      child: AnalogGauge(
                        value: reading.voltage,
                        min: 0,
                        max: 300,
                        label: compact ? '' : 'Voltage',
                        unit: 'V',
                        color: effectiveColor,
                      ),
                    ),
                  ),
                  SizedBox(
                    height: compact ? DesignTokens.spacingXSmall : DesignTokens.spacingSmall
                  ),
                ],
                if (shownMetrics.isNotEmpty &&
                    (displayMode == ChannelDisplayMode.digital ||
                        shownMetrics.length > 1))
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: DesignTokens.spacingXSmall
                    ),
                    child: Wrap(
                      spacing: DesignTokens.spacingSmall,
                      runSpacing: DesignTokens.spacingSmall,
                      alignment: WrapAlignment.start,
                      children: [
                        for (final metric in shownMetrics)
                          if (displayMode == ChannelDisplayMode.digital ||
                              metric.label != 'Voltage')
                            SizedBox(
                              width: compact ? 95 : 135,
                              child: metric,
                            ),
                      ],
                    ),
                  ),
                if (!compact) ...[
                  const SizedBox(height: DesignTokens.spacingSmall),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: isOff
                              ? null
                              : () async {
                                  final confirmed = await showOffConfirmationDialog(
                                    context,
                                    channel: reading.channelNumber,
                                  );
                                  if (confirmed) {
                                    await onOff();
                                  }
                                },
                          child: const Text('TURN OFF'),
                        ),
                      ),
                      const SizedBox(width: DesignTokens.spacingSmall),
                      IconButton.filledTonal(
                        onPressed: onDetails,
                        icon: const Icon(Icons.analytics_outlined),
                        tooltip: 'In-depth details',
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
