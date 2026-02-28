/// Alert Card — displays a single received SOS event.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:aftermath/core/app_theme.dart';
import 'package:aftermath/models/sos_event.dart';

class AlertCard extends StatelessWidget {
  const AlertCard({
    super.key,
    required this.event,
    this.onAcknowledge,
    this.onTap,
  });

  final SosEvent event;
  final VoidCallback? onAcknowledge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeFmt = DateFormat.Hms();
    final dateFmt = DateFormat.yMMMd();

    final statusColor = switch (event.status) {
      SosStatus.active => AppTheme.sosColor,
      SosStatus.relayed => Colors.orange,
      SosStatus.acknowledged => Colors.blue,
      SosStatus.resolved => AppTheme.safeColor,
      SosStatus.cancelled => Colors.grey,
    };

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: statusColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'SOS Alert',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      event.status.name.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Location
              Row(
                children: [
                  const Icon(Icons.location_on, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    '${event.latitude.toStringAsFixed(4)}, '
                    '${event.longitude.toStringAsFixed(4)}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
              const SizedBox(height: 4),

              // Time
              Row(
                children: [
                  const Icon(Icons.access_time, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    '${dateFmt.format(event.timestamp.toLocal())} '
                    '${timeFmt.format(event.timestamp.toLocal())}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 4),

              // Relay hops
              Row(
                children: [
                  const Icon(Icons.swap_horiz, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    '${event.relayHops} relay hop(s)',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),

              // Acknowledge button (only for active alerts)
              if (event.status == SosStatus.active ||
                  event.status == SosStatus.relayed) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonal(
                    onPressed: onAcknowledge,
                    child: const Text('Acknowledge'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
