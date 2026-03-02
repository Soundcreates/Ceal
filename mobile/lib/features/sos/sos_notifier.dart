/// SOS notifier.
library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aftermath/core/constants.dart';
import 'package:aftermath/core/poc_config.dart';
import 'package:aftermath/models/core_sos_packet.dart';
import 'package:aftermath/models/responder.dart';
import 'package:aftermath/models/sos_event.dart';
import 'package:aftermath/models/sos_type.dart';
import 'package:aftermath/providers.dart';
import 'package:aftermath/services/backend_service.dart';

enum SosPhase {
  idle,
  countdown,
  locating,
  broadcasting,
  awaitingAck,
  smsFallback,
  sent,
  cancelled,
  error,
}

class SosState {
  const SosState({
    this.phase = SosPhase.idle,
    this.countdownRemaining = kSosCancelCountdownSec,
    this.currentEvent,
    this.errorMessage,
    this.backendConfirmed = false,
    this.smsSent = false,
    this.sosType = SosType.general,
  });

  final SosPhase phase;
  final int countdownRemaining;
  final SosEvent? currentEvent;
  final String? errorMessage;

  /// True when the backend returned a 2xx for this SOS event.
  final bool backendConfirmed;

  /// True when SMS fallback was dispatched.
  final bool smsSent;

  /// The type of SOS being sent.
  final SosType sosType;

  SosState copyWith({
    SosPhase? phase,
    int? countdownRemaining,
    SosEvent? currentEvent,
    String? errorMessage,
    bool? backendConfirmed,
    bool? smsSent,
    SosType? sosType,
  }) {
    return SosState(
      phase: phase ?? this.phase,
      countdownRemaining: countdownRemaining ?? this.countdownRemaining,
      currentEvent: currentEvent ?? this.currentEvent,
      errorMessage: errorMessage ?? this.errorMessage,
      backendConfirmed: backendConfirmed ?? this.backendConfirmed,
      smsSent: smsSent ?? this.smsSent,
      sosType: sosType ?? this.sosType,
    );
  }
}

class SosNotifier extends StateNotifier<SosState> {
  SosNotifier(this._ref) : super(const SosState());

  final Ref _ref;
  Timer? _countdownTimer;
  Timer? _ackTimer;
  int _sequence = 0;

  void triggerSos({SosType type = SosType.general}) {
    if (state.phase != SosPhase.idle && state.phase != SosPhase.error) return;

    state = SosState(phase: SosPhase.countdown, sosType: type);
    _countdownTimer?.cancel();

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final remaining = state.countdownRemaining - 1;
      if (remaining <= 0) {
        timer.cancel();
        _commitSos();
      } else {
        state = state.copyWith(countdownRemaining: remaining);
      }
    });
  }

  void cancelSos() {
    _countdownTimer?.cancel();
    _ackTimer?.cancel();
    _ref.read(bleAdvertiserProvider).onBroadcastComplete = null;
    _ref.read(bleAdvertiserProvider).stopContinuousBroadcast();
    _ref.read(bleAdvertiserProvider).stopAdvertising();

    state = const SosState(phase: SosPhase.cancelled);

    Future<void>.delayed(const Duration(seconds: 2), () {
      if (state.phase == SosPhase.cancelled) {
        state = const SosState();
      }
    });
  }

  void reset() {
    _countdownTimer?.cancel();
    _ackTimer?.cancel();
    _ref.read(bleAdvertiserProvider).onBroadcastComplete = null;
    _ref.read(bleAdvertiserProvider).stopContinuousBroadcast();
    state = const SosState();
  }

  Future<void> _commitSos() async {
    state = state.copyWith(phase: SosPhase.broadcasting);

    final bleUid = await _ref.read(bleUidProvider.future);
    final seq = _sequence;
    _sequence = (_sequence + 1) & 0xFF;

    final corePacket = CoreSosPacket(
      version: kCorePacketVersion,
      flags: CoreSosPacket.buildFlags(sosActive: true, sosType: state.sosType),
      bleUid: bleUid,
      sequence: seq,
    );

    final dedupKey = 'uid:${corePacket.bleUidHex}:$seq';
    final event = SosEvent(
      id: dedupKey,
      bleUid: Uint8List.fromList(bleUid),
      flags: corePacket.flags,
      sequence: seq,
      timestamp: DateTime.now().toUtc(),
    );

    state = state.copyWith(currentEvent: event);

    // --- Get location (fast, ~1-2s) ---
    final pos = await _ref.read(locationServiceProvider).getCurrentPosition();
    if (pos != null) {
      event.receiverLocation = ReceiverLocation(
        lat: pos.latitude,
        lon: pos.longitude,
        accuracy: pos.accuracy,
      );
    }

    // --- Always enqueue locally so ConnectivityWorker can retry ---
    await _ref.read(queueServiceProvider).enqueue(event);

    // --- Register callback: send device SMS AFTER BLE advertising stops ---
    // SMS is deferred until the 60s BLE broadcast session completes so that
    // nearby mesh relayers have time to pick up the signal first.
    // After BLE stops, we:
    //   1. Fetch the victim's own profile from the backend (emergency contacts + medical info).
    //   2. Merge backend contacts with local contacts (backend takes priority).
    //   3. Include victim medical info in the SMS body.
    //   4. Send SMS to all resolved contacts.
    final advertiser = _ref.read(bleAdvertiserProvider);
    advertiser.onBroadcastComplete = () async {
      final sms = _ref.read(smsFallbackProvider);
      final backend = _ref.read(backendServiceProvider);
      state = state.copyWith(phase: SosPhase.smsFallback);

      // --- Fetch own profile from backend to get emergency contacts ---
      final bleUidHex = bleUid
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      debugPrint(
        '[SosNotifier] BLE broadcast ended — looking up own profile '
        'for uid=$bleUidHex from backend',
      );

      VictimProfile? profile;
      String? victimInfo;
      try {
        profile = await backend.lookupVictimProfile(bleUidHex);
      } catch (e) {
        debugPrint('[SosNotifier] Backend profile lookup failed: $e');
      }

      if (profile != null) {
        debugPrint(
          '[SosNotifier] Profile resolved: name=${profile.name} '
          'contacts=${profile.contacts.length} '
          'hasMedical=${profile.medical != null}',
        );

        // Build victim info string for SMS body.
        final parts = <String>[];
        if (profile.name?.isNotEmpty ?? false) {
          parts.add('Victim: ${profile.name}');
        }
        if (profile.phone?.isNotEmpty ?? false) {
          parts.add('Phone: ${profile.phone}');
        }
        final blood = profile.medical?.bloodGroup;
        if (blood?.isNotEmpty ?? false) parts.add('Blood group: $blood');
        final allergies = profile.medical?.allergies;
        if (allergies?.isNotEmpty ?? false) parts.add('Allergies: $allergies');
        final conditions = profile.medical?.conditions;
        if (conditions?.isNotEmpty ?? false) {
          parts.add('Conditions: $conditions');
        }
        if (parts.isNotEmpty) victimInfo = parts.join('\n');

        // Use backend-registered emergency contacts if available.
        if (profile.contacts.isNotEmpty) {
          final backendContacts = <EmergencyContact>[];
          for (final c in profile.contacts) {
            final phone = c.phone;
            if (phone != null && phone.isNotEmpty) {
              backendContacts.add(EmergencyContact(
                name: c.name ?? 'Emergency Contact',
                phone: phone,
              ));
            }
          }
          if (backendContacts.isNotEmpty) {
            debugPrint(
              '[SosNotifier] Using ${backendContacts.length} backend contacts '
              '(overriding ${sms.emergencyContacts.length} local contacts)',
            );
            sms.emergencyContacts = backendContacts;
          }
        }
      } else {
        debugPrint(
          '[SosNotifier] No backend profile — falling back to '
          '${sms.emergencyContacts.length} local emergency contacts',
        );
      }

      // Escalation operator always gets a direct device SMS copy.
      if (kEscalationPhone.isNotEmpty) {
        final already = sms.emergencyContacts
            .any((c) => c.phone == kEscalationPhone);
        if (!already) {
          sms.emergencyContacts = [
            ...sms.emergencyContacts,
            EmergencyContact(
              name: 'Emergency Operator',
              phone: kEscalationPhone,
            ),
          ];
        }
      }

      debugPrint(
        '[SosNotifier] Sending SMS to emergency contacts | '
        'enabled=${sms.enabled} contacts=${sms.emergencyContacts.length} '
        'numbers=[${sms.emergencyContacts.map((c) => c.phone).join(', ')}] '
        'hasVictimInfo=${victimInfo != null}',
      );

      final smsSent = await sms.sendSos(event, victimInfo: victimInfo);
      debugPrint('[SosNotifier] Device SMS sent to $smsSent contact(s)');
      state = state.copyWith(smsSent: smsSent > 0, phase: SosPhase.sent);
    };

    // --- Fire-and-forget BLE broadcast (runs for 60s, then triggers SMS) ---
    advertiser
        .broadcastCoreSos(corePacket)
        .then((_) {
          debugPrint(
            '[SosNotifier] Initial BLE burst cycle complete — continuous timer active',
          );
        })
        .catchError((Object e) {
          debugPrint('[SosNotifier] BLE broadcast error: $e');
        });

    // --- Attempt backend ingest (no Twilio — device SMS is the only channel) ---
    state = state.copyWith(phase: SosPhase.awaitingAck);
    final uploaded = await _ref.read(backendServiceProvider).ingestSos(event);

    state = state.copyWith(
      phase: SosPhase.broadcasting,
      backendConfirmed: uploaded,
    );
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _ackTimer?.cancel();
    super.dispose();
  }
}

final sosNotifierProvider = StateNotifierProvider<SosNotifier, SosState>((ref) {
  return SosNotifier(ref);
});
