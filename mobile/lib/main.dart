import 'dart:async';

import 'package:aftermath/core/app_theme.dart';
import 'package:aftermath/features/alerts/alert_list_screen.dart';
import 'package:aftermath/features/alerts/alerts_notifier.dart';
import 'package:aftermath/features/onboarding/permission_screen.dart';
import 'package:aftermath/features/onboarding/welcome_screen.dart';
import 'package:aftermath/features/settings/settings_screen.dart';
import 'package:aftermath/features/sos/sos_screen.dart';
import 'package:aftermath/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AfterMath',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      routes: {
        '/alerts': (_) => const AlertListScreen(),
        '/settings': (_) => const SettingsScreen(),
      },
      home: const AppBootstrapScreen(),
    );
  }
}

enum _OnboardingStep {
  welcome,
  permissions,
  home,
}

class AppBootstrapScreen extends ConsumerStatefulWidget {
  const AppBootstrapScreen({super.key});

  @override
  ConsumerState<AppBootstrapScreen> createState() => _AppBootstrapScreenState();
}

class _AppBootstrapScreenState extends ConsumerState<AppBootstrapScreen> {
  static const EventChannel _volumeEventChannel = EventChannel(
    'volume_trigger/events',
  );

  StreamSubscription<dynamic>? _volumeSubscription;
  _OnboardingStep _step = _OnboardingStep.welcome;

  @override
  void initState() {
    super.initState();
    _initServices();
    _listenVolumeEvents();
  }

  Future<void> _initServices() async {
    final settings = ref.read(settingsServiceProvider);
    await settings.init();

    final sms = ref.read(smsFallbackProvider);
    sms.emergencyContacts = await settings.loadContacts();
    sms.enabled = await settings.isSmsEnabled();

    final scanner = ref.read(bleScannerProvider);
    final reassembler = ref.read(packetReassemblerProvider);
    final relay = ref.read(meshRelayProvider);
    final alerts = ref.read(alertsNotifierProvider.notifier);

    // Scanner feeds CORE packets directly into the reassembler (V2: includes RSSI).
    scanner.onCorePacketReceived = reassembler.addCorePacket;

    // Reassembler feeds completed SOS events into relay + alerts (V2: includes RSSI).
    reassembler.onSosReassembled = (event, deviceId, rssi) {
      relay.onSosReceived(event, deviceId, rssi);
      alerts.addAlert(event);
    };

    ref.read(foregroundServiceProvider).init();
  }

  void _listenVolumeEvents() {
    _volumeSubscription = _volumeEventChannel
        .receiveBroadcastStream()
        .listen((dynamic event) {
      if (!mounted || event != 'double_volume_up') return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Double volume-up detected')),
      );
    });
  }

  @override
  void dispose() {
    _volumeSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    switch (_step) {
      case _OnboardingStep.welcome:
        return WelcomeScreen(
          onGetStarted: () {
            setState(() => _step = _OnboardingStep.permissions);
          },
        );
      case _OnboardingStep.permissions:
        return PermissionScreen(
          onComplete: () {
            setState(() => _step = _OnboardingStep.home);
          },
        );
      case _OnboardingStep.home:
        return const SosScreen();
    }
  }
}
