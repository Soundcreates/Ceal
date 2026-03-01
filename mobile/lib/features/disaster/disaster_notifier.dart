/// Disaster Notifier — Riverpod state management for disaster reporting.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aftermath/models/disaster_report.dart';
import 'package:aftermath/providers.dart';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

class DisasterFeedState {
  const DisasterFeedState({
    this.reports = const [],
    this.isLoading = false,
    this.isSubmitting = false,
    this.error,
    this.page = 1,
    this.hasMore = true,
    this.stats,
    this.categoryFilter,
  });

  final List<DisasterReport> reports;
  final bool isLoading;
  final bool isSubmitting;
  final String? error;
  final int page;
  final bool hasMore;
  final DisasterStats? stats;
  final String? categoryFilter;

  DisasterFeedState copyWith({
    List<DisasterReport>? reports,
    bool? isLoading,
    bool? isSubmitting,
    String? error,
    int? page,
    bool? hasMore,
    DisasterStats? stats,
    String? categoryFilter,
    bool clearError = false,
    bool clearFilter = false,
  }) {
    return DisasterFeedState(
      reports: reports ?? this.reports,
      isLoading: isLoading ?? this.isLoading,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      error: clearError ? null : (error ?? this.error),
      page: page ?? this.page,
      hasMore: hasMore ?? this.hasMore,
      stats: stats ?? this.stats,
      categoryFilter: clearFilter ? null : (categoryFilter ?? this.categoryFilter),
    );
  }
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class DisasterNotifier extends StateNotifier<DisasterFeedState> {
  DisasterNotifier(this._ref) : super(const DisasterFeedState());

  final Ref _ref;

  /// Load the first page of the verified disaster feed.
  Future<void> loadFeed({bool refresh = false}) async {
    if (state.isLoading) return;
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final backend = _ref.read(backendServiceProvider);
      final reports = await backend.fetchDisasterFeed(
        page: 1,
        limit: 20,
        category: state.categoryFilter,
      );
      state = state.copyWith(
        reports: reports,
        isLoading: false,
        page: 1,
        hasMore: reports.length >= 20,
      );
    } catch (e) {
      debugPrint('[DisasterNotifier] loadFeed error: $e');
      state = state.copyWith(isLoading: false, error: 'Failed to load feed');
    }
  }

  /// Load the next page (infinite scroll).
  Future<void> loadMore() async {
    if (state.isLoading || !state.hasMore) return;
    state = state.copyWith(isLoading: true);

    try {
      final backend = _ref.read(backendServiceProvider);
      final nextPage = state.page + 1;
      final reports = await backend.fetchDisasterFeed(
        page: nextPage,
        limit: 20,
        category: state.categoryFilter,
      );
      state = state.copyWith(
        reports: [...state.reports, ...reports],
        isLoading: false,
        page: nextPage,
        hasMore: reports.length >= 20,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Failed to load more');
    }
  }

  /// Set category filter and reload.
  Future<void> setCategory(String? category) async {
    if (category == state.categoryFilter) return;
    state = state.copyWith(
      categoryFilter: category,
      clearFilter: category == null,
    );
    await loadFeed(refresh: true);
  }

  /// Load stats.
  Future<void> loadStats() async {
    try {
      final backend = _ref.read(backendServiceProvider);
      final stats = await backend.fetchDisasterStats();
      if (stats != null) {
        state = state.copyWith(stats: stats);
      }
    } catch (e) {
      debugPrint('[DisasterNotifier] loadStats error: $e');
    }
  }

  /// Submit a new disaster report.
  Future<String?> submitReport({
    required Uint8List imageBytes,
    required String filename,
    required double lat,
    required double lon,
    String? description,
  }) async {
    state = state.copyWith(isSubmitting: true, clearError: true);

    try {
      final backend = _ref.read(backendServiceProvider);
      final result = await backend.submitDisasterReport(
        imageBytes: imageBytes,
        filename: filename,
        lat: lat,
        lon: lon,
        description: description,
      );

      if (result.success) {
        state = state.copyWith(isSubmitting: false);
        // Refresh the feed after successful submission.
        loadFeed(refresh: true);
        loadStats();
        return result.verificationStatus;
      } else {
        state = state.copyWith(
          isSubmitting: false,
          error: result.error ?? 'Submission failed',
        );
        return null;
      }
    } catch (e) {
      state = state.copyWith(isSubmitting: false, error: 'Network error');
      return null;
    }
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final disasterNotifierProvider =
    StateNotifierProvider<DisasterNotifier, DisasterFeedState>((ref) {
  return DisasterNotifier(ref);
});
