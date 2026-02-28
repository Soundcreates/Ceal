/// SOS Notifier — orchestrates the full SOS trigger → broadcast → fallback flow.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aftermath/core/constants.dart';
import 'package:aftermath/models/sos_event.dart';
import 'package:aftermath/providers.dart';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

enum SosPhase {
  /// Idle — no active SOS.
  idle,

  /// Countdown before committing the SOS.
  countdown,

  /// Acquiring GPS.
  locating,

  /// Broadcasting via BLE.
  broadcasting,

  /// Waiting for relay / backend ACK.
  awaitingAck,

  /// SMS fallback triggered.
  smsFallback,

  /// SOS successfully sent (at least one channel confirmed).
  sent,

  /// User cancelled during countdown.
  cancelled,

  /// An error occurred.
  error,
}

class SosState {
  const SosState({
    this.phase = SosPhase.idle,
    this.countdownRemaining = kSosCancelCountdownSec,
    this.currentEvent,
    this.errorMessage,
  });

  final SosPhase phase;
  final int countdownRemaining;
  final SosEvent? currentEvent;
  final String? errorMessage;

  SosState copyWith({
    SosPhase? phase,
    int? countdownRemaining,
    SosEvent? currentEvent,
    String? errorMessage,
  }) =>
      SosState(
        phase: phase ?? this.phase,
        countdownRemaining: countdownRemaining ?? this.countdownRemaining,
        currentEvent: currentEvent ?? this.currentEvent,
        errorMessage: errorMessage ?? this.errorMessage,
      );
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class SosNotifier extends StateNotifier<SosState> {
  SosNotifier(this._ref) : super(const SosState());

  final Ref _ref;
  Timer? _countdownTimer;
  Timer? _ackTimer;

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /// Initiate the SOS sequence with a cancel countdown.
  void triggerSos() {
    if (state.phase != SosPhase.idle && state.phase != SosPhase.error) return;

    state = const SosState(phase: SosPhase.countdown);

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

  /// Cancel the SOS during the countdown phase.
  void cancelSos() {
    _countdownTimer?.cancel();
    _ackTimer?.cancel();
    state = const SosState(phase: SosPhase.cancelled);

    // Reset back to idle after a short delay.
    Future.delayed(const Duration(seconds: 2), () {
      if (state.phase == SosPhase.cancelled) {
        state = const SosState();
      }
    });
  }

  /// Reset to idle (e.g. after dismissing an error).
  void reset() {
    _countdownTimer?.cancel();
    _ackTimer?.cancel();
    state = const SosState();
  }

  // -------------------------------------------------------------------------
  // Internal flow
  // -------------------------------------------------------------------------

  Future<void> _commitSos() async {
    // 1. Acquire GPS.
    state = state.copyWith(phase: SosPhase.locating);
    final locSvc = _ref.read(locationServiceProvider);
    final pos = await locSvc.getCurrentPosition();

    final lat = pos?.latitude ?? 0.0;
    final lon = pos?.longitude ?? 0.0;

    // 2. Build event.
    final enc = _ref.read(encryptionServiceProvider);
    final deviceHash = enc.deviceIdHash('local-device'); // TODO: real device ID

    final event = SosEvent(
      id: DateTime.now().millisecondsSinceEpoch.toRadixString(36),
      deviceIdHash: deviceHash,
      latitude: lat,
      longitude: lon,
      timestamp: DateTime.now().toUtc(),
    );

    state = state.copyWith(phase: SosPhase.broadcasting, currentEvent: event);

    // 3. Broadcast via BLE.
    final advertiser = _ref.read(bleAdvertiserProvider);
    try {
      await advertiser.broadcastSos(event);
    } catch (e) {
      debugPrint('[SosNotifier] BLE broadcast error: $e');
    }

    // 4. Attempt backend upload.
    state = state.copyWith(phase: SosPhase.awaitingAck);
    final backend = _ref.read(backendServiceProvider);
    final uploaded = await backend.ingestSos(event);

    if (uploaded) {
      state = state.copyWith(phase: SosPhase.sent);
      return;
    }

    // 5. Enqueue for mesh relay.
    final queue = _ref.read(queueServiceProvider);
    await queue.enqueue(event);

    // 6. Start SMS fallback timer.
    _ackTimer = Timer(kSmsFallbackTimeout, () => _triggerSmsFallback(event));

    // Optimistically mark as sent (BLE broadcast was done).
    state = state.copyWith(phase: SosPhase.sent);
  }

  Future<void> _triggerSmsFallback(SosEvent event) async {
    state = state.copyWith(phase: SosPhase.smsFallback);
    final sms = _ref.read(smsFallbackProvider);
    await sms.sendSos(event);
    state = state.copyWith(phase: SosPhase.sent);
  }

  // -------------------------------------------------------------------------
  // Dispose
  // -------------------------------------------------------------------------

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _ackTimer?.cancel();
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final sosNotifierProvider =
    StateNotifierProvider<SosNotifier, SosState>((ref) {
  return SosNotifier(ref);
});
