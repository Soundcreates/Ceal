/// AfterMath — Offline-first BLE emergency alert mesh network.
///
/// Entry point. Bootstraps services, configures routing, and wires up the
/// BLE scanner → PacketReassembler → MeshRelay → AlertsNotifier pipeline.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aftermath/core/app_theme.dart';
import 'package:aftermath/features/alerts/alert_list_screen.dart';
import 'package:aftermath/features/alerts/alerts_notifier.dart';
import 'package:aftermath/features/onboarding/permission_screen.dart';
import 'package:aftermath/features/onboarding/welcome_screen.dart';
import 'package:aftermath/features/settings/settings_screen.dart';
import 'package:aftermath/features/sos/sos_screen.dart';
import 'package:aftermath/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load runtime environment variables from the bundled .env asset.
  // Wrapped in try/catch so the app works in CI where the asset may be absent.
  try {
    await dotenv.load(fileName: '.env', mergeWith: {});
  } catch (_) {
    // No .env asset found — compiled defaults in Env will be used.
  }

  // Lock to portrait for the SOS trigger (large button needs stable layout).
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  runApp(const ProviderScope(child: AftermathApp()));
}

class AftermathApp extends ConsumerStatefulWidget {
  const AftermathApp({super.key});

  @override
  ConsumerState<AftermathApp> createState() => _AftermathAppState();
}

class _AftermathAppState extends ConsumerState<AftermathApp> {
  bool _onboarded = false;
  bool _permissionsGranted = false;

  @override
  void initState() {
    super.initState();
    _initServices();
  }

  /// Wire up the always-on BLE SOS relay + auto-escalation pipeline.
  Future<void> _initServices() async {
    // Initialise settings persistence.
    final settings = ref.read(settingsServiceProvider);
    await settings.init();

    // Load SMS contacts from persisted settings.
    final sms = ref.read(smsFallbackProvider);
    sms.emergencyContacts = await settings.loadContacts();
    sms.enabled = await settings.isSmsEnabled();

    // Legacy pipeline (kept for manual SOS trigger from UI):
    final scanner = ref.read(bleScannerProvider);
    final reassembler = ref.read(packetReassemblerProvider);
    final relay = ref.read(meshRelayProvider);
    final alerts = ref.read(alertsNotifierProvider.notifier);

    scanner.onCorePacketReceived = reassembler.addCorePacket;
    reassembler.onSosReassembled = (event, deviceId, rssi) {
      relay.onSosReceived(event, deviceId, rssi);
      alerts.addAlert(event);
    };

    // Always-on background relay — wire alerts notifier.
    final bgRelay = ref.read(backgroundRelayProvider);
    bgRelay.alertsNotifier = alerts;

    // Start foreground service (Android persistent notification).
    await ref.read(foregroundServiceProvider).init();

    // Start always-on BLE scanning + auto-escalation.
    await bgRelay.start();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AfterMath',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      home: _buildHome(),
      routes: {
        '/alerts': (_) => const AlertListScreen(),
        '/settings': (_) => const SettingsScreen(),
      },
    );
  }

  Widget _buildHome() {
    if (!_onboarded) {
      return WelcomeScreen(
        onGetStarted: () => setState(() => _onboarded = true),
      );
    }

    if (!_permissionsGranted) {
      return PermissionScreen(
        onComplete: () => setState(() => _permissionsGranted = true),
      );
    }

    return const SosScreen();
  }
}
