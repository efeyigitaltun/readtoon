import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/anilist_media.dart';
import '../../data/models/tracked_series.dart';
import '../providers/tracked_series_provider.dart';
import 'series_detail_screen.dart';

class TrackingListScreen extends ConsumerWidget {
  const TrackingListScreen({super.key});

  static const _filters = <(TrackingFilter, String)>[
    (TrackingFilter.all, 'Tümü'),
    (TrackingFilter.reading, 'Okuyorum'),
    (TrackingFilter.completed, 'Okudum'),
    (TrackingFilter.planToRead, 'Okuyacağım'),
    (TrackingFilter.dropped, 'Bıraktım'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allSeries = ref.watch(trackedSeriesProvider);
    final activeFilter = ref.watch(trackingFilterProvider);
    final visibleSeries = _filter(allSeries, activeFilter);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Takip Listem')),
      body: Column(
        children: [
          SizedBox(
            height: 58,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: _filters.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final (filter, label) = _filters[index];
                final selected = activeFilter == filter;
                return ChoiceChip(
                  label: Text(label),
                  selected: selected,
                  showCheckmark: false,
                  onSelected: (_) =>
                      ref.read(trackingFilterProvider.notifier).select(filter),
                  backgroundColor: AppColors.surface,
                  selectedColor: AppColors.accent,
                  side: BorderSide(
                    color: selected ? AppColors.accent : AppColors.divider,
                  ),
                  labelStyle: TextStyle(
                    color: selected
                        ? AppColors.background
                        : AppColors.textSecondary,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                );
              },
            ),
          ),
          Expanded(
            child: visibleSeries.isEmpty
                ? _TrackingEmptyState(
                    filter: activeFilter,
                    hasAnySeries: allSeries.isNotEmpty,
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: visibleSeries.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final series = visibleSeries[index];
                      return _TrackedSeriesCard(
                        series: series,
                        onTap: () => _openDetails(context, series),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  List<TrackedSeries> _filter(
    List<TrackedSeries> series,
    TrackingFilter filter,
  ) {
    if (filter == TrackingFilter.all) return series;
    final status = switch (filter) {
      TrackingFilter.all => null,
      TrackingFilter.reading => TrackedSeriesStatus.reading,
      TrackingFilter.completed => TrackedSeriesStatus.completed,
      TrackingFilter.planToRead => TrackedSeriesStatus.planToRead,
      TrackingFilter.dropped => TrackedSeriesStatus.dropped,
    };
    return series.where((item) => item.status == status).toList();
  }

  void _openDetails(BuildContext context, TrackedSeries series) {
    final media = AniListMedia(
      id: series.mediaId,
      title: series.title,
      coverUrl: series.coverUrl,
      bannerUrl: series.bannerUrl,
      totalChapters: series.totalChapters,
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => SeriesDetailScreen(media: media),
      ),
    );
  }
}

class _TrackedSeriesCard extends StatelessWidget {
  const _TrackedSeriesCard({required this.series, required this.onTap});

  final TrackedSeries series;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final total = series.totalChapters;
    final progress = total == null || total <= 0
        ? null
        : (series.chaptersRead / total).clamp(0.0, 1.0);

    return Material(
      color: AppColors.cardBackground,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CoverImage(url: series.coverUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        series.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _StatusBadge(status: series.status),
                          if (series.rating > 0)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.star_rounded,
                                  size: 16,
                                  color: AppColors.accent,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  series.rating.toStringAsFixed(1),
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                      const SizedBox(height: 9),
                      Text(
                        'Okunan: ${series.chaptersRead} / ${total ?? '?'}',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      if (progress != null) ...[
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 4,
                            color: AppColors.accent,
                            backgroundColor: AppColors.divider,
                          ),
                        ),
                      ],
                      if (series.reviewNote case final note?
                          when note.isNotEmpty) ...[
                        const SizedBox(height: 7),
                        Text(
                          note,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textDisabled,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoverImage extends StatelessWidget {
  const _CoverImage({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 82,
        height: 116,
        child: url.isEmpty
            ? const _CoverPlaceholder()
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    const _CoverPlaceholder(),
              ),
      ),
    );
  }
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.surface,
      child: Center(
        child: Icon(
          Icons.auto_stories_rounded,
          color: AppColors.textDisabled,
          size: 28,
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final TrackedSeriesStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.displayName,
        style: const TextStyle(
          color: AppColors.accent,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _TrackingEmptyState extends StatelessWidget {
  const _TrackingEmptyState({required this.filter, required this.hasAnySeries});

  final TrackingFilter filter;
  final bool hasAnySeries;

  @override
  Widget build(BuildContext context) {
    final filterLabel = switch (filter) {
      TrackingFilter.all => 'Tümü',
      TrackingFilter.reading => 'Okuyorum',
      TrackingFilter.completed => 'Okudum',
      TrackingFilter.planToRead => 'Okuyacağım',
      TrackingFilter.dropped => 'Bıraktım',
    };
    final (icon, title, message) = hasAnySeries
        ? (
            Icons.filter_list_off_rounded,
            'Bu filtrede seri yok',
            '“$filterLabel” filtresinde seri bulunamadı. Başka bir durum seçebilirsin.',
          )
        : (
            Icons.bookmarks_outlined,
            'Takip listen boş',
            'Keşfet bölümünden bir seri açıp durum veya puan vererek listene ekle.',
          );

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 54, color: AppColors.textDisabled),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
