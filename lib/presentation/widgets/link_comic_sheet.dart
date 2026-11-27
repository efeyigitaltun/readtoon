import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/comic_book.dart';
import '../../data/models/tracked_series.dart';

typedef LinkComicCallback = Future<void> Function(int? mediaId);

class LinkComicSheet extends StatelessWidget {
  const LinkComicSheet({
    required this.comic,
    required this.series,
    required this.onSelected,
    super.key,
  });

  final ComicBook comic;
  final List<TrackedSeries> series;
  final LinkComicCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.78;

    return SafeArea(
      top: false,
      child: SizedBox(
        height: maxHeight,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 12, 12),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'AniList serisiyle eşleştir',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Kapat',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  comic.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ),
            if (series.isEmpty)
              const Expanded(
                child: Padding(
                  padding: EdgeInsets.all(28),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.bookmarks_outlined,
                          size: 44,
                          color: AppColors.textDisabled,
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Takip edilen seri bulunamadı. Önce Keşfet bölümünden bir seriyi listene ekle.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  itemCount: series.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = series[index];
                    final selected = item.mediaId == comic.linkedMediaId;
                    return ListTile(
                      leading: _SeriesCover(url: item.coverUrl),
                      title: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textPrimary),
                      ),
                      subtitle: Text(
                        '${item.status.displayName}  •  ${item.chaptersRead}/${item.totalChapters ?? '?'} bölüm',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      trailing: selected
                          ? const Icon(
                              Icons.link_rounded,
                              color: AppColors.accent,
                            )
                          : const Icon(
                              Icons.add_link_rounded,
                              color: AppColors.textSecondary,
                            ),
                      onTap: () => onSelected(item.mediaId),
                    );
                  },
                ),
              ),
            if (comic.linkedMediaId != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: () => onSelected(null),
                    icon: const Icon(Icons.link_off_rounded),
                    label: const Text('Eşleşmeyi kaldır'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SeriesCover extends StatelessWidget {
  const _SeriesCover({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 44,
        height: 60,
        child: url.isEmpty
            ? const ColoredBox(
                color: AppColors.cardBackground,
                child: Icon(Icons.auto_stories_rounded, size: 20),
              )
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => const ColoredBox(
                  color: AppColors.cardBackground,
                  child: Icon(Icons.broken_image_outlined, size: 20),
                ),
              ),
      ),
    );
  }
}
