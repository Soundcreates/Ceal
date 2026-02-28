/// Alerts notifier.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aftermath/models/sos_event.dart';
import 'package:aftermath/providers.dart';
import 'package:aftermath/services/backend_service.dart';

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
  }) {
    return AlertsState(
      alerts: alerts ?? this.alerts,
      isLoading: isLoading ?? this.isLoading,
      lastError: lastError,
    );
  }
}

class AlertsNotifier extends StateNotifier<AlertsState> {
  AlertsNotifier(this._backend) : super(const AlertsState());

  final BackendService _backend;

  void addAlert(SosEvent event) {
    if (state.alerts.any((e) => e.id == event.id)) return;
    state = state.copyWith(alerts: [event, ...state.alerts]);
  }

  void clearResolved() {
    state = state.copyWith(
      alerts: state.alerts.where((e) => e.status != SosStatus.resolved).toList(),
    );
  }

  void clearAll() {
    state = state.copyWith(alerts: []);
  }

  Future<void> fetchFromBackend() async {
    state = state.copyWith(isLoading: true, lastError: null);
    try {
      final remote = await _backend.fetchActiveEvents();
      final merged = <String, SosEvent>{
        for (final e in state.alerts) e.id: e,
        for (final e in remote) e.id: e,
      };

      final sorted = merged.values.toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

      state = state.copyWith(alerts: sorted, isLoading: false);
    } catch (e) {
      debugPrint('[AlertsNotifier] fetchFromBackend error: $e');
      state = state.copyWith(isLoading: false, lastError: 'Could not reach server');
    }
  }

  Future<void> acknowledge(String sosId) async {
    _updateLocalStatus(sosId, SosStatus.acknowledged);
    try {
      await _backend.acknowledgeSos(sosId);
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

final alertsNotifierProvider =
    StateNotifierProvider<AlertsNotifier, AlertsState>((ref) {
  return AlertsNotifier(ref.watch(backendServiceProvider));
});
