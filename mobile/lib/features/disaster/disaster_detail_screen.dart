/// Disaster Detail Screen — full detail view of a single disaster report.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:aftermath/core/app_theme.dart';
import 'package:aftermath/core/nb_components.dart';
import 'package:aftermath/models/disaster_report.dart';
import 'package:aftermath/providers.dart';

class DisasterDetailScreen extends ConsumerStatefulWidget {
  const DisasterDetailScreen({super.key, required this.reportId});

  final String reportId;

  @override
  ConsumerState<DisasterDetailScreen> createState() =>
      _DisasterDetailScreenState();
}

class _DisasterDetailScreenState extends ConsumerState<DisasterDetailScreen> {
  DisasterReport? _report;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  Future<void> _loadReport() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final backend = ref.read(backendServiceProvider);
    final report = await backend.fetchDisasterReport(widget.reportId);

    if (mounted) {
      setState(() {
        _report = report;
        _isLoading = false;
        _error = report == null ? 'Failed to load report' : null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Report Detail')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorView(error: _error!, onRetry: _loadReport)
              : _report != null
                  ? _DetailBody(report: _report!)
                  : const SizedBox.shrink(),
    );
  }
}

// ---------------------------------------------------------------------------
// Detail body
// ---------------------------------------------------------------------------

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.report});

  final DisasterReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFmt = DateFormat.yMMMd();
    final timeFmt = DateFormat.Hms();
    final severityColor = _severityColor(report.severityScore);

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero image
          Container(
            width: double.infinity,
            height: 260,
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
                child: Icon(Icons.broken_image,
                    size: 64,
                    color: AppTheme.nbInk.withValues(alpha: 0.2)),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Category + severity row
                Row(
                  children: [
                    NBIconBox(
                      icon: _categoryIcon(report.category),
                      size: 44,
                      bgColor: severityColor.withValues(alpha: 0.15),
                      color: severityColor,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            report.categoryLabel,
                            style: theme.textTheme.headlineSmall,
                          ),
                          Text(
                            report.severityLabel,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: severityColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    NBBadge(
                      label: report.statusLabel.toUpperCase(),
                      color: _statusColor(report.verificationStatus)
                          .withValues(alpha: 0.2),
                      textColor: _statusColor(report.verificationStatus),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Description
                if (report.description != null &&
                    report.description!.isNotEmpty) ...[
                  NBSectionHeader(label: 'Description', icon: Icons.notes),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: NBCard(
                      shadow: false,
                      padding: const EdgeInsets.all(14),
                      child: Text(
                        report.description!,
                        style: theme.textTheme.bodyLarge,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // Info rows
                NBSectionHeader(label: 'Details', icon: Icons.info_outline),
                const SizedBox(height: 8),
                NBCard(
                  shadow: false,
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      _InfoRow(
                        icon: Icons.location_on,
                        label: 'Location',
                        value:
                            '${report.lat.toStringAsFixed(6)}, ${report.lon.toStringAsFixed(6)}',
                      ),
                      const Divider(height: 16, thickness: 1),
                      _InfoRow(
                        icon: Icons.access_time,
                        label: 'Reported',
                        value:
                            '${dateFmt.format(report.createdAt.toLocal())} at ${timeFmt.format(report.createdAt.toLocal())}',
                      ),
                      const Divider(height: 16, thickness: 1),
                      _InfoRow(
                        icon: Icons.speed,
                        label: 'Severity',
                        value:
                            '${report.severityScore}/5 — ${report.severityLabel}',
                        valueColor: severityColor,
                      ),
                      const Divider(height: 16, thickness: 1),
                      _InfoRow(
                        icon: Icons.psychology,
                        label: 'AI Confidence',
                        value:
                            '${(report.llmConfidence * 100).toStringAsFixed(1)}%',
                        valueColor: AppTheme.nbOk,
                      ),
                      if (report.authorityStatus != AuthorityStatus.none) ...[
                        const Divider(height: 16, thickness: 1),
                        _InfoRow(
                          icon: Icons.shield,
                          label: 'Authority',
                          value: report.authorityLabel,
                          valueColor: AppTheme.nbAccent2,
                        ),
                      ],
                    ],
                  ),
                ),

                // Rejection reason
                if (report.rejectionReason != null &&
                    report.rejectionReason!.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  NBSectionHeader(
                      label: 'Rejection Reason', icon: Icons.cancel),
                  const SizedBox(height: 8),
                  NBCard(
                    shadow: false,
                    color: AppTheme.nbError.withValues(alpha: 0.05),
                    borderColor: AppTheme.nbError,
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      report.rejectionReason!,
                      style: const TextStyle(
                        color: AppTheme.nbError,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
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

  static Color _statusColor(VerificationStatus status) => switch (status) {
        VerificationStatus.verified => AppTheme.nbOk,
        VerificationStatus.rejected => AppTheme.nbError,
        VerificationStatus.flagged => AppTheme.nbWarn,
        VerificationStatus.pending => AppTheme.nbInfo,
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

// ---------------------------------------------------------------------------
// Info row
// ---------------------------------------------------------------------------

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.nbInk.withValues(alpha: 0.4)),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppTheme.nbInk.withValues(alpha: 0.5),
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: valueColor ?? AppTheme.nbInk,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Error view
// ---------------------------------------------------------------------------

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          NBIconBox(
            icon: Icons.error_outline,
            size: 56,
            bgColor: AppTheme.nbError.withValues(alpha: 0.1),
            color: AppTheme.nbError,
          ),
          const SizedBox(height: 16),
          Text(error, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          NBButton(
            label: 'Retry',
            onPressed: onRetry,
            icon: Icons.refresh,
          ),
        ],
      ),
    );
  }
}
