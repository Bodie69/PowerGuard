import 'dart:async';

import 'package:flutter/material.dart';
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

  static const _pages = [
    DashboardPage(),
    SchedulesPage(),
    OffHistoryPage(),
    SettingsPage(),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _alertSubscription ??= context
        .read<RealtimeAlertService>()
        .alerts
        .listen(_showAlert);
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
