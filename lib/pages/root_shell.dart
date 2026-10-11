import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:provider/provider.dart';

import '../services/realtime_alert_service.dart';
import '../theme/app_theme.dart';
import 'dashboard_page.dart';
import 'off_history_page.dart';
import 'schedules_page.dart';
import 'settings_page.dart';

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;
  StreamSubscription<AppAlert>? _alertSubscription;
  bool _overcurrentDialogShowing = false;

  static const _pages = [
    DashboardPage(),
    SchedulesPage(),
    OffHistoryPage(),
    SettingsPage(),
  ];

  @override
  void initState() {
    super.initState();
    // The overcurrent watch itself runs in the foreground-service isolate
    // (OvercurrentTaskHandler) so it keeps working while the app is
    // backgrounded; this just surfaces it as an in-app dialog when the app
    // happens to be open.
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _alertSubscription ??= context
        .read<RealtimeAlertService>()
        .alerts
        .listen(_showAlert);
  }

  void _onTaskData(Object data) {
    if (!mounted) return;
    if (data is! Map || data['event'] != 'overcurrent') return;
    if (_overcurrentDialogShowing) return;

    final channel = data['channel'] as int;
    final current = (data['current'] as num).toDouble();
    _overcurrentDialogShowing = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(
          Icons.warning_amber_rounded,
          color: AppColors.danger,
          size: 40,
        ),
        title: const Text('Overcurrent Detected'),
        content: Text(
          'Computer $channel is drawing ${current.toStringAsFixed(1)} A, '
          'above the 1 A safety limit.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Acknowledge'),
          ),
        ],
      ),
    ).then((_) {
      _overcurrentDialogShowing = false;
      FlutterForegroundTask.sendDataToTask({'ack': true});
    });
  }

  void _showAlert(AppAlert alert) {
    if (!mounted) return;
    final color = switch (alert.level) {
      AppAlertLevel.danger => AppColors.danger,
      AppAlertLevel.warning => AppColors.warning,
      AppAlertLevel.info => Theme.of(context).colorScheme.primary,
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: color,
        content: Text(alert.message),
      ),
    );
  }

  @override
  void dispose() {
    _alertSubscription?.cancel();
    FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.schedule_outlined),
            selectedIcon: Icon(Icons.schedule),
            label: 'Schedules',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'Off History',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
