/// Alerts Notifier — manages received SOS alerts from BLE scanning.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aftermath/models/sos_event.dart';

class AlertsNotifier extends StateNotifier<List<SosEvent>> {
  AlertsNotifier() : super([]);

  /// Add a newly received SOS event to the top of the list.
  void addAlert(SosEvent event) {
    // Deduplicate by ID.
    if (state.any((e) => e.id == event.id)) return;
    state = [event, ...state];
  }

  /// Mark an alert as acknowledged.
  void acknowledge(String sosId) {
    state = [
      for (final e in state)
        if (e.id == sosId)
          SosEvent(
            id: e.id,
            deviceIdHash: e.deviceIdHash,
            latitude: e.latitude,
            longitude: e.longitude,
            timestamp: e.timestamp,
            status: SosStatus.acknowledged,
            relayHops: e.relayHops,
            message: e.message,
          )
        else
          e,
    ];
  }

  /// Remove resolved alerts.
  void clearResolved() {
    state = state.where((e) => e.status != SosStatus.resolved).toList();
  }

  /// Clear all alerts.
  void clearAll() {
    state = [];
  }
}

final alertsNotifierProvider =
    StateNotifierProvider<AlertsNotifier, List<SosEvent>>((ref) {
  return AlertsNotifier();
});
