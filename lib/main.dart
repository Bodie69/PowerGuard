import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'models/channel_reading.dart';
import 'models/device.dart';
import 'models/off_log.dart';
import 'models/off_schedule.dart';
import 'pages/login_page.dart';
import 'pages/root_shell.dart';
import 'pages/welcome_page.dart';
import 'services/dashboard_layout_controller.dart';
import 'services/foreground_alarm_service.dart';
import 'services/realtime_alert_service.dart';
import 'services/supabase_service.dart';
import 'services/theme_controller.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();

  await dotenv.load(fileName: '.env');

  if (!Config.isConfigured) {
    runApp(const _ConfigErrorApp());
    return;
  }

  try {
    await Supabase.initialize(
      url: Config.supabaseUrl,
      publishableKey: Config.supabaseAnonKey,
    );
  } catch (e, stack) {
    developer.log('Supabase initialization failed', error: e, stackTrace: stack);
    runApp(const _ConfigErrorApp());
    return;
  }

  final themeController = ThemeController();
  await themeController.load();

  final dashboardLayoutController = DashboardLayoutController();
  await dashboardLayoutController.load();

  runApp(
    MainApp(
      themeController: themeController,
      dashboardLayoutController: dashboardLayoutController,
    ),
  );
}

class MainApp extends StatelessWidget {
  const MainApp({
    super.key,
    required this.themeController,
    required this.dashboardLayoutController,
  });

  final ThemeController themeController;
  final DashboardLayoutController dashboardLayoutController;

  @override
  Widget build(BuildContext context) {
    final client = Supabase.instance.client;
    final supabaseService = SupabaseService(client);

    return MultiProvider(
      providers: [
        Provider<SupabaseService>.value(value: supabaseService),
        ChangeNotifierProvider<ThemeController>.value(value: themeController),
        ChangeNotifierProvider<DashboardLayoutController>.value(
          value: dashboardLayoutController,
        ),
        Provider<RealtimeAlertService>(
          create: (_) => RealtimeAlertService(client),
          dispose: (_, service) => service.dispose(),
        ),
        StreamProvider<List<Device>>(
          create: (_) => supabaseService.devicesStream(),
          initialData: const [],
          catchError: (_, error) {
            developer.log('Error in devicesStream', error: error);
            return [];
          },
        ),
        StreamProvider<List<ChannelReading>>(
          create: (_) => supabaseService.channelsStream(),
          initialData: const [],
          catchError: (_, error) {
            developer.log('Error in channelsStream', error: error);
            return [];
          },
        ),
        StreamProvider<List<OffSchedule>>(
          create: (_) => supabaseService.schedulesStream(),
          initialData: const [],
          catchError: (_, error) {
            developer.log('Error in schedulesStream', error: error);
            return [];
          },
        ),
        StreamProvider<List<OffLog>>(
          create: (_) => supabaseService.offLogsStream(),
          initialData: const [],
          catchError: (_, error) {
            developer.log('Error in offLogsStream', error: error);
            return [];
          },
        ),
      ],
      child: Consumer<ThemeController>(
        builder: (context, theme, _) {
          return MaterialApp(
            title: 'PowerGuard IoT',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(
              theme.accentColor,
              cardRadius: theme.cardRadius,
              visualDensity: theme.visualDensity,
            ),
            darkTheme: AppTheme.dark(
              theme.accentColor,
              cardRadius: theme.cardRadius,
              trueBlack: theme.useTrueBlack,
              visualDensity: theme.visualDensity,
            ),
            themeMode: theme.themeMode,
            home: const _AuthGate(),
          );
        },
      ),
    );
  }
}

class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  bool _pastWelcome = false;
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    final service = context.read<SupabaseService>();
    if (service.isAuthenticated) {
      ForegroundAlarmService.start();
    }
    _authSubscription = service.authStateChanges.listen((state) {
      if (state.event == AuthChangeEvent.signedOut) {
        ForegroundAlarmService.stop();
        if (mounted) setState(() => _pastWelcome = false);
      } else if (state.event == AuthChangeEvent.signedIn) {
        ForegroundAlarmService.start();
      }
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = context.read<SupabaseService>();
    return StreamBuilder<AuthState>(
      stream: service.authStateChanges,
      builder: (context, snapshot) {
        if (service.isAuthenticated) {
          return const RootShell();
        }
        if (!_pastWelcome) {
          return WelcomePage(
            onGetStarted: () => setState(() => _pastWelcome = true),
          );
        }
        return const LoginPage();
      },
    );
  }
}

class _ConfigErrorApp extends StatelessWidget {
  const _ConfigErrorApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PowerGuard IoT',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.settings_suggest, size: 56),
                const SizedBox(height: 16),
                Text(
                  'Supabase is not configured',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Edit the .env file in the project root and set '
                  'SUPABASE_URL and SUPABASE_ANON_KEY to the values from '
                  'your Supabase Dashboard (Project Settings > API), then '
                  'restart the app.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
