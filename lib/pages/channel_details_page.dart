import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/channel_reading.dart';
import '../models/off_log.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../theme/design_tokens.dart';
import '../widgets/analog_gauge.dart';
import '../widgets/elevated_metric_card.dart';
import '../widgets/off_confirmation_dialog.dart';
import '../widgets/sparkline_chart.dart';
import '../widgets/status_chip.dart';

class ChannelDetailsPage extends StatefulWidget {
  const ChannelDetailsPage({
    super.key,
    required this.channelNumber,
  });

  final int channelNumber;

  @override
  State<ChannelDetailsPage> createState() => _ChannelDetailsPageState();
}

class _ChannelDetailsPageState extends State<ChannelDetailsPage> {
  final List<double> _history = [];
  static const int _maxHistory = 50;

  @override
  Widget build(BuildContext context) {
    final readings = context.watch<List<ChannelReading>>();
    final reading = readings.firstWhere(
      (r) => r.channelNumber == widget.channelNumber,
      orElse: () => ChannelReading(
        id: 'placeholder-${widget.channelNumber}',
        deviceId: 'unknown',
        channelNumber: widget.channelNumber,
        voltage: 0.0,
        current: 0.0,
        power: 0.0,
        energy: 0.0,
        frequency: 0.0,
        powerFactor: 1.0,
        breakerStatus: 'OFF',
        updatedAt: DateTime.now(),
      ),
    );

    final offLogs = context.watch<List<OffLog>>().where(
      (l) => l.channel == widget.channelNumber,
    ).toList();

    // Update history for sparkline
    if (_history.isEmpty || _history.last != reading.power) {
      _history.add(reading.power);
      if (_history.length > _maxHistory) {
        _history.removeAt(0);
      }
    }

    final isOff = reading.isOff;

    return Scaffold(
      appBar: AppBar(
        title: Text('Channel ${widget.channelNumber} Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {}, // Handled by stream
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(DesignTokens.spacingLarge),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context, reading),
            const SizedBox(height: DesignTokens.spacingLarge),
            _buildMainGauges(context, reading),
            const SizedBox(height: DesignTokens.spacingLarge),
            _buildTrendSection(context),
            const SizedBox(height: DesignTokens.spacingLarge),
            _buildTechnicalSpecs(context, reading),
            const SizedBox(height: DesignTokens.spacingLarge),
            _buildOffHistory(context, offLogs),
            const SizedBox(height: DesignTokens.spacingXLarge),
            ElevatedButton.icon(
              onPressed: isOff ? null : () => _confirmOff(context, reading),
              icon: const Icon(Icons.power_settings_new),
              label: const Text('TURN OFF'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  vertical: DesignTokens.spacingMedium
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ChannelReading reading) {
    final isOff = reading.isOff;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Status: ${isOff ? "OFF" : "ON"}',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: isOff ? AppColors.danger : AppColors.success,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Last updated: ${reading.updatedAt.hour}:${reading.updatedAt.minute}:${reading.updatedAt.second}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        StatusChip(
          label: isOff ? 'OFF' : 'ON',
          color: isOff ? AppColors.danger : AppColors.success,
        ),
      ],
    );
  }

  Widget _buildMainGauges(BuildContext context, ChannelReading reading) {
    return Row(
      children: [
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(DesignTokens.spacingMedium),
              child: AnalogGauge(
                value: reading.voltage,
                min: 0,
                max: 300,
                label: 'Voltage',
                unit: 'V',
                color: AppColors.primary,
              ),
            ),
          ),
        ),
        const SizedBox(width: DesignTokens.spacingSmall),
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(DesignTokens.spacingMedium),
              child: AnalogGauge(
                value: reading.current,
                min: 0,
                max: 32,
                label: 'Current',
                unit: 'A',
                color: AppColors.warning,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTrendSection(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingMedium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Power Consumption Trend (W)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: DesignTokens.spacingMedium),
            SizedBox(
              height: 120,
              child: SparklineChart(
                data: _history,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTechnicalSpecs(BuildContext context, ChannelReading reading) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Advanced Metrics',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: DesignTokens.spacingSmall),
        Wrap(
          spacing: DesignTokens.spacingSmall,
          runSpacing: DesignTokens.spacingSmall,
          children: [
            SizedBox(
              width: (MediaQuery.of(context).size.width - 
                     (DesignTokens.spacingLarge * 2) - 
                     DesignTokens.spacingSmall) / 2,
              child: ElevatedMetricCard(
                label: 'Active Power',
                value: '${reading.power.toStringAsFixed(1)} W',
                color: AppColors.primary,
              ),
            ),
            SizedBox(
              width: (MediaQuery.of(context).size.width - 
                     (DesignTokens.spacingLarge * 2) - 
                     DesignTokens.spacingSmall) / 2,
              child: ElevatedMetricCard(
                label: 'Total Energy',
                value: '${reading.energy.toStringAsFixed(2)} kWh',
                color: Colors.green,
              ),
            ),
            SizedBox(
              width: (MediaQuery.of(context).size.width - 
                     (DesignTokens.spacingLarge * 2) - 
                     DesignTokens.spacingSmall) / 2,
              child: ElevatedMetricCard(
                label: 'Frequency',
                value: '${reading.frequency.toStringAsFixed(1)} Hz',
                color: Colors.orange,
              ),
            ),
            SizedBox(
              width: (MediaQuery.of(context).size.width - 
                     (DesignTokens.spacingLarge * 2) - 
                     DesignTokens.spacingSmall) / 2,
              child: ElevatedMetricCard(
                label: 'Power Factor',
                value: reading.powerFactor.toStringAsFixed(2),
                color: Colors.purple,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildOffHistory(BuildContext context, List<OffLog> logs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recent Off Events',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (logs.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('No off events recorded for this channel.'),
          )
        else
          ...logs.take(3).map((log) => Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              leading: const Icon(Icons.history, color: AppColors.danger),
              title: Text(log.reason),
              subtitle: Text('${log.timestamp.day}/${log.timestamp.month} - ${log.voltage}V'),
              trailing: Text('${log.current}A'),
            ),
          )),
      ],
    );
  }

  Future<void> _confirmOff(BuildContext context, ChannelReading reading) async {
    final service = context.read<SupabaseService>();
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showOffConfirmationDialog(
      context,
      channel: reading.channelNumber,
    );
    
    if (!confirmed || !mounted) return;

    final deviceId = reading.deviceId;
    final channelNumber = reading.channelNumber;
    
    await service.sendOffCommand(
      deviceId: deviceId,
      channel: channelNumber,
    );

    if (mounted) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Off command sent!')),
      );
    }
  }
}
