/// Alert List Screen — shows all received SOS alerts (BLE + backend).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aftermath/core/app_theme.dart';
import 'package:aftermath/features/alerts/alert_card.dart';
import 'package:aftermath/features/alerts/alerts_notifier.dart';
import 'package:aftermath/models/sos_event.dart';

class AlertListScreen extends ConsumerStatefulWidget {
  const AlertListScreen({super.key});

  @override
  ConsumerState<AlertListScreen> createState() => _AlertListScreenState();
}

class _AlertListScreenState extends ConsumerState<AlertListScreen> {
  @override
  void initState() {
    super.initState();
    // Fetch from backend as soon as the screen opens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(alertsNotifierProvider.notifier).fetchFromBackend();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(alertsNotifierProvider);
    final notifier = ref.read(alertsNotifierProvider.notifier);
    final alerts = state.alerts;

    // Show error snackbar when the backend is unreachable.
    ref.listen<AlertsState>(alertsNotifierProvider, (prev, next) {
      if (next.lastError != null && next.lastError != prev?.lastError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.lastError!),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Received Alerts'),
        actions: [
          // Refresh from backend
          state.isLoading
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh from server',
                  onPressed: () => notifier.fetchFromBackend(),
                ),
          if (alerts.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: 'Clear all',
              onPressed: () => _confirmClear(context, notifier),
            ),
        ],
      ),
      body: alerts.isEmpty
          ? state.isLoading
              ? const Center(child: CircularProgressIndicator())
              : const _EmptyState()
          : ListView.builder(
              padding: const EdgeInsets.only(top: 8, bottom: 80),
              itemCount: alerts.length,
              itemBuilder: (context, index) {
                final event = alerts[index];
                return AlertCard(
                  event: event,
                  onAcknowledge: event.status == SosStatus.active ||
                          event.status == SosStatus.relayed
                      ? () => notifier.acknowledge(event.id)
                      : null,
                  onTap: () {
                    // Future: open map view centred on this alert.
                  },
                );
              },
            ),
    );
  }

  void _confirmClear(BuildContext context, AlertsNotifier notifier) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all alerts?'),
        content: const Text(
            'This will remove all received alerts from the list.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              notifier.clearAll();
              Navigator.of(ctx).pop();
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppTheme.nbInk.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(AppTheme.nbRadius),
              border: Border.all(
                color: AppTheme.nbInk.withValues(alpha: 0.15),
                width: AppTheme.nbBorder,
              ),
            ),
            child: Icon(Icons.notifications_none, size: 36, color: AppTheme.nbInk.withValues(alpha: 0.3)),
          ),
          const SizedBox(height: 16),
          Text(
            'No alerts received',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: AppTheme.nbInk.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Nearby SOS signals will appear here.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
