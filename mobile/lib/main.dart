/// CEAL — Civic Emergency Access Layer. Offline-first BLE emergency alert mesh network.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:aftermath/core/app_theme.dart';
import 'package:aftermath/core/env.dart';
import 'package:aftermath/features/alerts/alert_list_screen.dart';
import 'package:aftermath/features/alerts/alerts_notifier.dart';
import 'package:aftermath/features/alerts/victim_detail_popup.dart';
import 'package:aftermath/features/disaster/disaster_feed_screen.dart';
import 'package:aftermath/features/onboarding/aadhaar_qr_screen.dart';
import 'package:aftermath/features/onboarding/manual_kyc_form_screen.dart';
import 'package:aftermath/features/onboarding/permission_screen.dart';
import 'package:aftermath/features/onboarding/signup_screen.dart';
import 'package:aftermath/features/onboarding/welcome_screen.dart';
import 'package:aftermath/features/settings/settings_screen.dart';
import 'package:aftermath/features/sos/sos_notifier.dart';
import 'package:aftermath/features/sos/sos_screen.dart';
import 'package:aftermath/models/sos_type.dart';
import 'package:aftermath/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  runApp(const ProviderScope(child: MyApp()));
}

/// Global navigator key so services (e.g. notification taps) can show dialogs
/// without requiring a widget-tree [BuildContext].
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CEAL',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      routes: {
        '/alerts': (_) => const AlertListScreen(),
        '/settings': (_) => const SettingsScreen(),
        '/disasters': (_) => const DisasterFeedScreen(),
      },
      home: const AppBootstrapScreen(),
    );
  }
}

enum _OnboardingStep {
  welcome,
  permissions,
  signup,
  aadhaarQr,
  manualKyc,
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
  StreamSubscription<Map<String, dynamic>>? _notifTapSubscription;
  _OnboardingStep _step = _OnboardingStep.welcome;
  bool _isInitializing = true;

  @override
  void initState() {
    super.initState();
    _initServices().whenComplete(() {
      if (mounted) setState(() => _isInitializing = false);
    });
    _listenVolumeEvents();
  }

  /// Wire up the always-on BLE SOS relay + auto-escalation pipeline.
  Future<void> _initServices() async {
    final settings = ref.read(settingsServiceProvider);
    await settings.init();

    // Load persisted auth token from secure storage (set during signup).
    const storage = FlutterSecureStorage();
    final storedToken = await storage.read(key: 'aftermath_auth_token');
    if (storedToken != null && storedToken.isNotEmpty) {
      ref.read(backendServiceProvider).authToken = storedToken;
      _step = _OnboardingStep.home;
    }

    // Dev override: .env API_AUTH_TOKEN always takes precedence when set.
    if (Env.apiAuthToken.isNotEmpty) {
      ref.read(backendServiceProvider).authToken = Env.apiAuthToken;
      _step = _OnboardingStep.home;
    }

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

    // Always-on background relay — wire alerts notifier + own BLE UID.
    final bgRelay = ref.read(backgroundRelayProvider);
    bgRelay.alertsNotifier = alerts;

    // Set own BLE UID so the relay skips self-originated packets.
    final ownUid = await ref.read(bleUidProvider.future);
    bgRelay.ownBleUidHex =
        ownUid.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    debugPrint('[AppBootstrap] Own BLE UID = ${bgRelay.ownBleUidHex}');

    // Start foreground service (Android persistent notification).
    await ref.read(foregroundServiceProvider).init();

    // Start always-on BLE scanning + auto-escalation.
    await bgRelay.start();

    // Listen for notification body taps → show victim-detail popup.
    final notifService = ref.read(sosNotificationServiceProvider);
    _notifTapSubscription = notifService.onNotificationTap.listen((data) {
      final ctx = navigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        showVictimDetailPopup(ctx, VictimDetailData.fromJsonMap(data));
      }
    });
  }

  void _listenVolumeEvents() {
    _volumeSubscription = _volumeEventChannel.receiveBroadcastStream().listen((
      dynamic event,
    ) {
      if (!mounted || event is! String) return;

      final sosType = SosType.fromEventString(event);

      // Ensure the user is on the SOS screen.
      if (_step != _OnboardingStep.home) {
        setState(() => _step = _OnboardingStep.home);
      }

      // Fire SOS with the detected type (starts the cancellable countdown).
      HapticFeedback.heavyImpact();
      ref.read(sosNotifierProvider.notifier).triggerSos(type: sosType);
    });
  }

  @override
  void dispose() {
    _volumeSubscription?.cancel();
    _notifTapSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
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
            setState(() => _step = _OnboardingStep.signup);
          },
        );
      case _OnboardingStep.signup:
        return SignupScreen(
          onComplete: () {
            setState(() => _step = _OnboardingStep.home);
          },
        );
      case _OnboardingStep.aadhaarQr:
        return AadhaarQrScreen(
          onComplete: () {
            setState(() => _step = _OnboardingStep.home);
          },
          onSkip: () {
            setState(() => _step = _OnboardingStep.manualKyc);
          },
        );
      case _OnboardingStep.manualKyc:
        return ManualKycFormScreen(
          onComplete: () {
            setState(() => _step = _OnboardingStep.home);
          },
          onBackToScan: () {
            setState(() => _step = _OnboardingStep.signup);
          },
        );
      case _OnboardingStep.home:
        return const SosScreen();
    }
  }
}
