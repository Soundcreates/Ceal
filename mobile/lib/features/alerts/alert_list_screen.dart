/// Alert List Screen — shows all received SOS alerts.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aftermath/features/alerts/alert_card.dart';
import 'package:aftermath/features/alerts/alerts_notifier.dart';

class AlertListScreen extends ConsumerWidget {
  const AlertListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(alertsNotifierProvider);
    final notifier = ref.read(alertsNotifierProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Received Alerts'),
        actions: [
          if (alerts.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: 'Clear all',
              onPressed: () => _confirmClear(context, notifier),
            ),
        ],
      ),
      body: alerts.isEmpty
          ? const _EmptyState()
          : ListView.builder(
              padding: const EdgeInsets.only(top: 8, bottom: 80),
              itemCount: alerts.length,
              itemBuilder: (context, index) {
                final event = alerts[index];
                return AlertCard(
                  event: event,
                  onAcknowledge: () => notifier.acknowledge(event.id),
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
        content: const Text('This will remove all received alerts from the list.'),
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
          Icon(Icons.notifications_none, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No alerts received',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: Colors.grey),
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
