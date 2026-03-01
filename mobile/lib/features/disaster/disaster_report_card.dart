/// Disaster Report Card — a single report item in the feed list.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:aftermath/core/app_theme.dart';
import 'package:aftermath/core/nb_components.dart';
import 'package:aftermath/models/disaster_report.dart';

class DisasterReportCard extends StatelessWidget {
  const DisasterReportCard({
    super.key,
    required this.report,
    this.onTap,
  });

  final DisasterReport report;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeFmt = DateFormat.Hms();
    final dateFmt = DateFormat.yMMMd();

    final severityColor = _severityColor(report.severityScore);
    final categoryIcon = _categoryIcon(report.category);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: GestureDetector(
        onTap: onTap,
        child: NBCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image
              Container(
                height: 180,
                width: double.infinity,
                decoration: BoxDecoration(
                  border: const Border(
                    bottom: BorderSide(
                      color: AppTheme.nbInk,
                      width: AppTheme.nbBorder,
                    ),
                  ),
                  color: AppTheme.nbInk.withValues(alpha: 0.05),
                ),
                child: Image.network(
                  report.imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Center(
                    child: Icon(
                      Icons.broken_image,
                      size: 48,
                      color: AppTheme.nbInk.withValues(alpha: 0.2),
                    ),
                  ),
                  loadingBuilder: (_, child, progress) {
                    if (progress == null) return child;
                    return Center(
                      child: CircularProgressIndicator(
                        value: progress.expectedTotalBytes != null
                            ? progress.cumulativeBytesLoaded /
                                progress.expectedTotalBytes!
                            : null,
                        strokeWidth: 2,
                      ),
                    );
                  },
                ),
              ),

              // Content
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header row: category + severity + time
                    Row(
                      children: [
                        NBIconBox(
                          icon: categoryIcon,
                          size: 34,
                          bgColor: severityColor.withValues(alpha: 0.15),
                          color: severityColor,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                report.categoryLabel,
                                style: theme.textTheme.titleMedium,
                              ),
                              Text(
                                '${dateFmt.format(report.createdAt.toLocal())} · '
                                '${timeFmt.format(report.createdAt.toLocal())}',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        NBBadge(
                          label: 'SEV ${report.severityScore}',
                          color: severityColor.withValues(alpha: 0.2),
                          textColor: severityColor,
                        ),
                      ],
                    ),

                    // Description
                    if (report.description != null &&
                        report.description!.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        report.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],

                    const SizedBox(height: 10),

                    // Bottom row: location + confidence
                    Row(
                      children: [
                        Icon(Icons.location_on,
                            size: 14,
                            color: AppTheme.nbInk.withValues(alpha: 0.4)),
                        const SizedBox(width: 4),
                        Text(
                          '${report.lat.toStringAsFixed(4)}, ${report.lon.toStringAsFixed(4)}',
                          style: theme.textTheme.bodySmall,
                        ),
                        const Spacer(),
                        if (report.llmConfidence > 0)
                          Text(
                            '${(report.llmConfidence * 100).toStringAsFixed(0)}% conf.',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.nbOk.withValues(alpha: 0.8),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static Color _severityColor(int severity) => switch (severity) {
        1 => AppTheme.nbOk,
        2 => AppTheme.nbInfo,
        3 => AppTheme.nbWarn,
        4 => AppTheme.nbError,
        5 => const Color(0xFF991B1B),
        _ => AppTheme.nbInk,
      };

  static IconData _categoryIcon(DisasterCategory category) =>
      switch (category) {
        DisasterCategory.fire => Icons.local_fire_department,
        DisasterCategory.flood => Icons.water,
        DisasterCategory.accident => Icons.car_crash,
        DisasterCategory.infrastructure => Icons.domain_disabled,
        DisasterCategory.medical => Icons.local_hospital,
        DisasterCategory.other => Icons.report,
      };
}
