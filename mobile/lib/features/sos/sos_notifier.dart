/// SOS Notifier — orchestrates the full SOS trigger → broadcast → fallback flow.
///
/// V2: privacy-first — no GPS in BLE packets. The BLE UID and a wrapping
/// sequence counter are broadcast. GPS is only acquired for SMS fallback.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aftermath/core/constants.dart';
import 'package:aftermath/models/core_sos_packet.dart';
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

  /// Wrapping sequence counter (0-255) for CORE V2 packets.
  int _sequence = 0;

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

  /// Cancel the SOS during any active phase.
  void cancelSos() {
    _countdownTimer?.cancel();
    _ackTimer?.cancel();

    // Stop any in-progress BLE advertising.
    final advertiser = _ref.read(bleAdvertiserProvider);
    advertiser.stopAdvertising();

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
    // 1. Load persistent BLE UID.
    final bleUid = await _ref.read(bleUidProvider.future);
    final seq = _sequence;
    _sequence = (_sequence + 1) & 0xFF; // wrap at 255

    final corePacket = CoreSosPacket(
      version: kCorePacketVersion,
      flags: CoreSosPacket.buildFlags(sosActive: true),
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

    state = state.copyWith(phase: SosPhase.broadcasting, currentEvent: event);

    // 2. Broadcast 10-byte CORE V2 packet (no GPS, UID only).
    final advertiser = _ref.read(bleAdvertiserProvider);
    try {
      await advertiser.broadcastCoreSos(corePacket);
    } catch (e) {
      debugPrint('[SosNotifier] BLE broadcast error: $e');
      state = state.copyWith(
        phase: SosPhase.error,
        errorMessage: 'BLE broadcast failed: $e',
      );
      // Continue to backend/SMS fallback despite BLE failure.
    }

    // 3. Attach receiver's own location for backend upload.
    final locSvc = _ref.read(locationServiceProvider);
    final pos = await locSvc.getCurrentPosition();
    if (pos != null) {
      event.receiverLocation = ReceiverLocation(
        lat: pos.latitude,
        lon: pos.longitude,
        accuracy: pos.accuracy,
      );
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
    // SMS fallback acquires GPS independently for the SMS body.
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
