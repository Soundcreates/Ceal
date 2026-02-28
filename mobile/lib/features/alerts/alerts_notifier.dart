/// Alerts Notifier — manages received SOS alerts, with backend integration.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aftermath/models/sos_event.dart';
import 'package:aftermath/providers.dart';
import 'package:aftermath/services/backend_service.dart';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

class AlertsState {
  const AlertsState({
    this.alerts = const [],
    this.isLoading = false,
    this.lastError,
  });

  final List<SosEvent> alerts;
  final bool isLoading;
  final String? lastError;

  AlertsState copyWith({
    List<SosEvent>? alerts,
    bool? isLoading,
    String? lastError,
  }) =>
      AlertsState(
        alerts: alerts ?? this.alerts,
        isLoading: isLoading ?? this.isLoading,
        lastError: lastError,
      );
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class AlertsNotifier extends StateNotifier<AlertsState> {
  AlertsNotifier(this._backend) : super(const AlertsState());

  final BackendService _backend;

  // -------------------------------------------------------------------------
  // Local (BLE-received) mutations
  // -------------------------------------------------------------------------

  /// Add a newly received SOS event (from BLE) to the top of the list.
  void addAlert(SosEvent event) {
    if (state.alerts.any((e) => e.id == event.id)) return;
    state = state.copyWith(alerts: [event, ...state.alerts]);
  }

  /// Remove resolved alerts from local state.
  void clearResolved() {
    state = state.copyWith(
      alerts:
          state.alerts.where((e) => e.status != SosStatus.resolved).toList(),
    );
  }

  /// Clear all alerts from local state.
  void clearAll() {
    state = state.copyWith(alerts: []);
  }

  // -------------------------------------------------------------------------
  // Backend integration
  // -------------------------------------------------------------------------

  /// Pull active SOS events from the backend and merge into local list.
  /// Remote events take precedence for shared IDs; local BLE-only events kept.
  Future<void> fetchFromBackend() async {
    state = state.copyWith(isLoading: true, lastError: null);
    try {
      final remote = await _backend.fetchActiveEvents();

      // Merge: map of id → event. Remote overwrites local for the same ID.
      final merged = <String, SosEvent>{
        for (final e in state.alerts) e.id: e,
        for (final e in remote) e.id: e,
      };

      final sorted = merged.values.toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

      state = state.copyWith(alerts: sorted, isLoading: false);
    } catch (e) {
      debugPrint('[AlertsNotifier] fetchFromBackend error: $e');
      state = state.copyWith(
        isLoading: false,
        lastError: 'Could not reach server',
      );
    }
  }

  /// Acknowledge an SOS both locally and on the backend.
  Future<void> acknowledge(String sosId) async {
    // Optimistic local update first so the UI responds immediately.
    _updateLocalStatus(sosId, SosStatus.acknowledged);

    try {
      final ok = await _backend.acknowledgeSos(sosId);
      if (!ok) {
        debugPrint('[AlertsNotifier] Backend ack returned failure for $sosId');
      }
    } catch (e) {
      debugPrint('[AlertsNotifier] Backend ack error for $sosId: $e');
    }
  }

  void _updateLocalStatus(String sosId, SosStatus newStatus) {
    state = state.copyWith(
      alerts: [
        for (final e in state.alerts)
          if (e.id == sosId)
            SosEvent(
              id: e.id,
              bleUid: e.bleUid,
              flags: e.flags,
              sequence: e.sequence,
              timestamp: e.timestamp,
              status: newStatus,
              relayHops: e.relayHops,
              receiverLocation: e.receiverLocation,
              rssi: e.rssi,
              message: e.message,
            )
          else
            e,
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final alertsNotifierProvider =
    StateNotifierProvider<AlertsNotifier, AlertsState>((ref) {
  return AlertsNotifier(ref.watch(backendServiceProvider));
});
