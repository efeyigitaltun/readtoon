import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/comic_book.dart';
import '../providers/library_provider.dart';

/// Kütüphane ızgarasındaki tek bir manga kartı.
/// Kapak görseli, başlık ve ilerleme çubuğunu içerir.
class ComicCoverCard extends ConsumerWidget {
  final ComicBook comic;
  final VoidCallback onTap;

  const ComicCoverCard({super.key, required this.comic, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(comicProgressProvider(comic));
    final history = ref.watch(readHistoryProvider(comic.id)).valueOrNull;
    final readingStatus = comic.readingStatus(history);
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppConstants.coverBorderRadius),
        child: Container(
          color: AppColors.cardBackground,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ─── Kapak Görseli ─────────────────────────────────────────
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _CoverImage(comic: comic),
                    if (readingStatus == ComicReadingStatus.read)
                      Positioned(
                        top: 7,
                        left: 7,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.background.withValues(alpha: 0.82),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.check_circle_rounded,
                                size: 13,
                                color: AppColors.accent,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Okundu',
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Material(
                        color: AppColors.background.withValues(alpha: 0.78),
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => ref
                              .read(libraryProvider.notifier)
                              .toggleFavorite(comic.id),
                          child: SizedBox(
                            width: 34,
                            height: 34,
                            child: Icon(
                              comic.isFavorite
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              size: 19,
                              color: comic.isFavorite
                                  ? AppColors.accent
                                  : AppColors.textPrimary.withValues(
                                      alpha: 0.72,
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ─── Başlık + İlerleme Çubuğu ─────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      comic.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                        height: 1.3,
                      ),
                    ),
                    if (progress > 0) ...[
                      const SizedBox(height: 5),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: progress,
                          backgroundColor: AppColors.divider,
                          color: AppColors.accent,
                          minHeight: 3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kapak görselini gösterir; yoksa şık bir placeholder sunar.
class _CoverImage extends StatelessWidget {
  final ComicBook comic;
  const _CoverImage({required this.comic});

  @override
  Widget build(BuildContext context) {
    if (comic.coverImageBytes != null && comic.coverImageBytes!.isNotEmpty) {
      return Image.memory(
        comic.coverImageBytes!,
        fit: BoxFit.cover,
        width: double.infinity,
        // Hatalı resim verisine karşı fallback
        errorBuilder: (_, __, ___) => _Placeholder(title: comic.title),
      );
    }

    return _Placeholder(title: comic.title);
  }
}

/// Kapak görseli yokken gösterilen koyu placeholder.
class _Placeholder extends StatelessWidget {
  final String title;
  const _Placeholder({required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.shimmerBase,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.auto_stories_rounded,
              size: 36,
              color: AppColors.accent,
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
