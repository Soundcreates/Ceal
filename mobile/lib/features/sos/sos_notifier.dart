/// SOS notifier.
library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aftermath/core/constants.dart';
import 'package:aftermath/models/core_sos_packet.dart';
import 'package:aftermath/models/sos_event.dart';
import 'package:aftermath/models/sos_type.dart';
import 'package:aftermath/providers.dart';

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

    // --- Fire-and-forget BLE broadcast (runs independently for 60s) ---
    _ref
        .read(bleAdvertiserProvider)
        .broadcastCoreSos(corePacket)
        .then((_) {
          debugPrint(
            '[SosNotifier] Initial BLE burst cycle complete — continuous timer active',
          );
        })
        .catchError((Object e) {
          debugPrint('[SosNotifier] BLE broadcast error: $e');
        });

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

    // --- ALWAYS send device SMS to emergency contacts immediately ---
    state = state.copyWith(phase: SosPhase.smsFallback);
    final smsSent = await _ref.read(smsFallbackProvider).sendSos(event);
    debugPrint('[SosNotifier] Device SMS sent to $smsSent contact(s)');

    // --- Attempt backend ingest (triggers Twilio on server side too) ---
    state = state.copyWith(phase: SosPhase.awaitingAck);
    final uploaded = await _ref.read(backendServiceProvider).ingestSos(event);

    state = state.copyWith(
      phase: SosPhase.sent,
      backendConfirmed: uploaded,
      smsSent: smsSent > 0,
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
