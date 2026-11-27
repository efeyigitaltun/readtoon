import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../core/constants/app_constants.dart';
import '../../data/models/tracked_series.dart';
import 'auth_provider.dart';
import 'firestore_sync_service_provider.dart';

/// Hive'daki AniList takip kayıtlarını ve ekrandaki kopyalarını senkron tutar.
class TrackedSeriesNotifier extends Notifier<List<TrackedSeries>> {
  Box<TrackedSeries> get _box =>
      Hive.box<TrackedSeries>(AppConstants.trackedSeriesBox);

  @override
  List<TrackedSeries> build() {
    final items = _box.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return items;
  }

  TrackedSeries? findByMediaId(int mediaId) {
    for (final series in state) {
      if (series.mediaId == mediaId) return series;
    }
    return null;
  }

  Future<void> save(TrackedSeries series) async {
    series.updatedAt = DateTime.now();
    await _box.put(series.mediaId, series);

    final updated = [
      for (final item in state)
        if (item.mediaId != series.mediaId) item,
      series,
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    state = updated;

    final user = ref.read(authStateProvider).valueOrNull;
    if (user != null) {
      unawaited(_syncToCloud(user.uid, series));
    }
  }

  Future<void> _syncToCloud(String uid, TrackedSeries series) async {
    try {
      await ref.read(firestoreSyncServiceProvider).upsertSeries(uid, series);
    } catch (error) {
      debugPrint('Seri buluta eşitlenemedi: $error');
    }
  }

  /// Yerel dosya son sayfasına ilk kez ulaştığında serinin bölüm sayısını artırır.
  /// Aynı dosyanın tekrar okunması ikinci bir artış oluşturmaz.
  Future<bool> countLocalComicCompletion({
    required int mediaId,
    required String comicId,
  }) async {
    final series = findByMediaId(mediaId);
    if (series == null || series.completedLocalComicIds.contains(comicId)) {
      return false;
    }
    final total = series.totalChapters;
    if (total != null && series.chaptersRead >= total) return false;

    final previousChaptersRead = series.chaptersRead;
    series.completedLocalComicIds.add(comicId);
    series.chaptersRead++;
    try {
      await save(series);
      return true;
    } catch (_) {
      series.completedLocalComicIds.remove(comicId);
      series.chaptersRead = previousChaptersRead;
      rethrow;
    }
  }
}

enum TrackingFilter { all, reading, completed, planToRead, dropped }

class TrackingFilterNotifier extends Notifier<TrackingFilter> {
  @override
  TrackingFilter build() => TrackingFilter.all;

  void select(TrackingFilter filter) => state = filter;
}

final trackingFilterProvider =
    NotifierProvider<TrackingFilterNotifier, TrackingFilter>(
      TrackingFilterNotifier.new,
    );

final trackedSeriesProvider =
    NotifierProvider<TrackedSeriesNotifier, List<TrackedSeries>>(
      TrackedSeriesNotifier.new,
    );
