import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/channel_history_entry.dart';
import '../models/channel_monthly_energy.dart';
import '../models/channel_reading.dart';
import '../models/device.dart';
import '../models/off_log.dart';
import '../services/device_online_debouncer.dart';
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
  List<ChannelHistoryEntry> _historyPoints = [];
  List<ChannelMonthlyEnergy> _monthlyHistory = [];
  double? _monthStartEnergy;
  StreamSubscription<List<ChannelHistoryEntry>>? _historySub;
  StreamSubscription<List<ChannelMonthlyEnergy>>? _monthlyHistorySub;
  Timer? _ticker;
  final _onlineDebouncer = DeviceOnlineDebouncer();

  @override
  void initState() {
    super.initState();
    final service = context.read<SupabaseService>();
    _historySub = service.channelHistoryStream(widget.channelNumber).listen((points) {
      if (mounted) setState(() => _historyPoints = points);
    });
    _monthlyHistorySub = service.monthlyEnergyStream(widget.channelNumber).listen((months) {
      if (mounted) setState(() => _monthlyHistory = months);
    });
    service.monthStartEnergy(widget.channelNumber).then((value) {
      if (mounted) setState(() => _monthStartEnergy = value);
    });
    // Device.isOnline depends on wall-clock time, not just on new readings
    // arriving, so re-check on a timer to zero the meter once the device
    // goes stale -- same as the dashboard's channel grid. DeviceOnlineDebouncer
    // needs this to tick faster than isOnline's own staleness window to
    // confirm an offline flip promptly.
    _ticker = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _historySub?.cancel();
    _monthlyHistorySub?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final readings = context.watch<List<ChannelReading>>();
    final rawReading = readings.firstWhere(
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

    // Single-device app for now, same assumption channelsStream() makes.
    final devices = context.watch<List<Device>>();
    final isOnline = _onlineDebouncer.update(devices.isEmpty ? null : devices.first);
    // Same as the dashboard's channel grid: zero the meter values whenever
    // the device is offline OR this channel's own breaker is OFF, so a
    // computer that's off never shows stale/leftover live values just
    // because the ESP32 itself is still online.
    final reading =
        (!isOnline || rawReading.isOff) ? rawReading.zeroed() : rawReading;

    final offLogs = context.watch<List<OffLog>>().where(
      (l) => l.channel == widget.channelNumber,
    ).toList();

    // energy is the PZEM's cumulative kWh register, so this month's usage
    // is just how much it's climbed since the first reading this month.
    final latestEnergy =
        _historyPoints.isEmpty ? null : _historyPoints.last.energy;
    final rawMonthKwh = (latestEnergy != null && _monthStartEnergy != null)
        ? latestEnergy - _monthStartEnergy!
        : null;
    // A negative delta means the PZEM's energy register was reset
    // mid-month (e.g. power-cycled) -- the baseline no longer applies.
    final monthKwh = (rawMonthKwh != null && rawMonthKwh >= 0) ? rawMonthKwh : null;

    final isOff = reading.isOff;

    return Scaffold(
      appBar: AppBar(
        title: Text('Computer ${widget.channelNumber} Details'),
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
            _buildHeader(context, reading, isOnline),
            const SizedBox(height: DesignTokens.spacingLarge),
            _buildMainGauges(context, reading),
            const SizedBox(height: DesignTokens.spacingLarge),
            _buildTrendSection(context, _historyPoints, monthKwh),
            const SizedBox(height: DesignTokens.spacingLarge),
            _buildMonthlyHistory(context, _monthlyHistory),
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

  Widget _buildHeader(BuildContext context, ChannelReading reading, bool isOnline) {
    final isOff = reading.isOff;
    // The breaker status is frozen at whatever it last reported once the
    // device stops checking in, so it can't be trusted as the real status --
    // show OFFLINE instead, same as the dashboard's channel cards.
    final statusLabel = !isOnline ? 'OFFLINE' : (isOff ? 'OFF' : 'ON');
    final statusColor = !isOnline
        ? AppColors.danger
        : (isOff ? AppColors.danger : AppColors.success);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Status: $statusLabel',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: statusColor,
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
          label: statusLabel,
          color: statusColor,
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

  Widget _buildTrendSection(
    BuildContext context,
    List<ChannelHistoryEntry> historyPoints,
    double? monthKwh,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spacingMedium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Power Consumption Trend (W)',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: DesignTokens.spacingSmall),
                Text(
                  monthKwh == null
                      ? 'This month: —'
                      : 'This month: ${monthKwh.toStringAsFixed(2)} kWh',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.right,
                ),
              ],
            ),
            const SizedBox(height: DesignTokens.spacingMedium),
            SizedBox(
              height: 120,
              child: SparklineChart(
                data: historyPoints.map((p) => p.power).toList(),
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Past months' totals, archived server-side once each month completes
  /// (see the archive-monthly-energy cron job) so they're preserved even
  /// after channel_history's raw rows for that month get pruned.
  Widget _buildMonthlyHistory(BuildContext context, List<ChannelMonthlyEnergy> months) {
    final monthFormat = DateFormat('MMMM yyyy');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Monthly Consumption History',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (months.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'No monthly totals archived yet -- check back after this '
              'month ends.',
            ),
          )
        else
          ...months.map((entry) => Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              leading: const Icon(Icons.calendar_month, color: AppColors.primary),
              title: Text(monthFormat.format(entry.month)),
              trailing: Text(
                '${entry.consumedKwh.toStringAsFixed(2)} kWh',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          )),
      ],
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
