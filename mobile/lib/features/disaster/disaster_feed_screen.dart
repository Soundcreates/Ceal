/// Disaster Feed Screen — paginated list of verified community disaster reports.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aftermath/core/app_theme.dart';
import 'package:aftermath/core/nb_components.dart';
import 'package:aftermath/models/disaster_report.dart';
import 'package:aftermath/features/disaster/disaster_notifier.dart';
import 'package:aftermath/features/disaster/disaster_report_card.dart';
import 'package:aftermath/features/disaster/disaster_detail_screen.dart';
import 'package:aftermath/features/disaster/submit_report_screen.dart';

class DisasterFeedScreen extends ConsumerStatefulWidget {
  const DisasterFeedScreen({super.key});

  @override
  ConsumerState<DisasterFeedScreen> createState() => _DisasterFeedScreenState();
}

class _DisasterFeedScreenState extends ConsumerState<DisasterFeedScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(disasterNotifierProvider.notifier).loadFeed();
      ref.read(disasterNotifierProvider.notifier).loadStats();
    });
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(disasterNotifierProvider.notifier).loadMore();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(disasterNotifierProvider);
    final notifier = ref.read(disasterNotifierProvider.notifier);

    // Show error snackbar.
    ref.listen<DisasterFeedState>(disasterNotifierProvider, (prev, next) {
      if (next.error != null && next.error != prev?.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.error!)),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Disaster Reports'),
        actions: [
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
                  tooltip: 'Refresh',
                  onPressed: () {
                    notifier.loadFeed(refresh: true);
                    notifier.loadStats();
                  },
                ),
        ],
      ),
      body: Column(
        children: [
          // Stats bar
          if (state.stats != null) _StatsBar(stats: state.stats!),

          // Category filter chips
          _CategoryFilter(
            selected: state.categoryFilter,
            onSelected: notifier.setCategory,
          ),

          // Report list
          Expanded(
            child: state.reports.isEmpty
                ? state.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : const _EmptyState()
                : RefreshIndicator(
                    onRefresh: () async {
                      await notifier.loadFeed(refresh: true);
                      await notifier.loadStats();
                    },
                    child: ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.only(top: 4, bottom: 100),
                      itemCount: state.reports.length + (state.hasMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index >= state.reports.length) {
                          return const Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        final report = state.reports[index];
                        return DisasterReportCard(
                          report: report,
                          onTap: () {
                            Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) =>
                                  DisasterDetailScreen(reportId: report.id),
                            ));
                          },
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: GestureDetector(
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const SubmitReportScreen(),
          ));
        },
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: AppTheme.nbError,
            borderRadius: BorderRadius.zero,
            border: Border.all(color: AppTheme.nbInk, width: AppTheme.nbBorder),
            boxShadow: AppTheme.nbShadow,
          ),
          child: const Icon(Icons.camera_alt, color: AppTheme.nbCard, size: 28),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stats bar
// ---------------------------------------------------------------------------

class _StatsBar extends StatelessWidget {
  const _StatsBar({required this.stats});

  final DisasterStats stats;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: NBCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _StatItem(
              label: 'Total',
              value: '${stats.totalReports}',
              color: AppTheme.nbAccent,
            ),
            _StatItem(
              label: 'Verified',
              value: '${stats.verified}',
              color: AppTheme.nbOk,
            ),
            _StatItem(
              label: 'Pending',
              value: '${stats.pending}',
              color: AppTheme.nbWarn,
            ),
            _StatItem(
              label: 'Rejected',
              value: '${stats.rejected}',
              color: AppTheme.nbError,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: AppTheme.nbInk.withValues(alpha: 0.5),
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Category filter chips
// ---------------------------------------------------------------------------

class _CategoryFilter extends StatelessWidget {
  const _CategoryFilter({required this.selected, required this.onSelected});

  final String? selected;
  final ValueChanged<String?> onSelected;

  static const _categories = [
    ('All', null),
    ('🔥 Fire', 'fire'),
    ('🌊 Flood', 'flood'),
    ('💥 Accident', 'accident'),
    ('🏗️ Infra', 'infrastructure'),
    ('🏥 Medical', 'medical'),
    ('📦 Other', 'other'),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final (label, value) = _categories[index];
          final isActive = selected == value;
          return GestureDetector(
            onTap: () => onSelected(value),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isActive ? AppTheme.nbAccent : AppTheme.nbCard,
                borderRadius: BorderRadius.zero,
                border: Border.all(
                  color: AppTheme.nbInk,
                  width: AppTheme.nbBorder,
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isActive ? AppTheme.nbCard : AppTheme.nbInk,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

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
            child: Icon(Icons.report_off,
                size: 36,
                color: AppTheme.nbInk.withValues(alpha: 0.3)),
          ),
          const SizedBox(height: 16),
          Text(
            'No verified reports yet',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppTheme.nbInk.withValues(alpha: 0.5),
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Be the first to report a disaster in your area.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
