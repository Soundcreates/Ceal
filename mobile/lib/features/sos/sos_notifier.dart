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

    try {
      await _ref.read(bleAdvertiserProvider).broadcastCoreSos(corePacket);
    } catch (e) {
      debugPrint('[SosNotifier] BLE broadcast error: $e');
      state = state.copyWith(
        phase: SosPhase.error,
        errorMessage: 'BLE broadcast failed: $e',
      );
    }

    final pos = await _ref.read(locationServiceProvider).getCurrentPosition();
    if (pos != null) {
      event.receiverLocation = ReceiverLocation(
        lat: pos.latitude,
        lon: pos.longitude,
        accuracy: pos.accuracy,
      );
    }

    state = state.copyWith(phase: SosPhase.awaitingAck);

    final uploaded = await _ref.read(backendServiceProvider).ingestSos(event);
    if (uploaded) {
      state = state.copyWith(phase: SosPhase.sent, backendConfirmed: true);
      return;
    }

    // Backend unreachable — queue locally and go straight to SMS fallback
    // rather than waiting kSmsFallbackTimeout (30s) since we already know
    // the server is down.
    await _ref.read(queueServiceProvider).enqueue(event);
    await _triggerSmsFallback(event);
  }

  Future<void> _triggerSmsFallback(SosEvent event) async {
    state = state.copyWith(phase: SosPhase.smsFallback);
    await _ref.read(smsFallbackProvider).sendSos(event);
    state = state.copyWith(phase: SosPhase.sent, smsSent: true);
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
