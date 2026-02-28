/// Alert Card — displays a single received SOS event.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:aftermath/core/app_theme.dart';
import 'package:aftermath/core/nb_components.dart';
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
      SosStatus.active => AppTheme.nbError,
      SosStatus.relayed => AppTheme.nbWarn,
      SosStatus.acknowledged => AppTheme.nbAccent2,
      SosStatus.resolved => AppTheme.nbOk,
      SosStatus.cancelled => AppTheme.nbInk.withValues(alpha: 0.3),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: GestureDetector(
        onTap: onTap,
        child: NBCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  NBIconBox(
                    icon: Icons.warning_amber_rounded,
                    size: 34,
                    bgColor: statusColor.withValues(alpha: 0.15),
                    color: statusColor,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'SOS Alert',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  NBBadge(
                    label: event.status.name.toUpperCase(),
                    color: statusColor.withValues(alpha: 0.2),
                    textColor: statusColor,
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // V2: show receiver location (proximity, not victim's GPS).
              if (event.receiverLocation != null)
                Row(
                  children: [
                    Icon(Icons.location_on, size: 16, color: AppTheme.nbInk.withValues(alpha: 0.5)),
                    const SizedBox(width: 4),
                    Text(
                      '≈ ${event.receiverLocation!.lat.toStringAsFixed(4)}, '
                      '${event.receiverLocation!.lon.toStringAsFixed(4)}',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              const SizedBox(height: 4),

              // Time
              Row(
                children: [
                  Icon(Icons.access_time, size: 16, color: AppTheme.nbInk.withValues(alpha: 0.5)),
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
                  Icon(Icons.swap_horiz, size: 16, color: AppTheme.nbInk.withValues(alpha: 0.5)),
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
                  child: NBButton(
                    label: 'Acknowledge',
                    onPressed: onAcknowledge,
                    icon: Icons.check,
                    color: AppTheme.nbAccent2,
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
