import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/anilist_media.dart';
import '../../data/services/anilist_service.dart';
import '../providers/discover_provider.dart';
import 'series_detail_screen.dart';

enum DiscoverCategory {
  trending('Trend Olanlar'),
  popularManhwa('Popüler Manhwalar'),
  topRated('En Yüksek Puanlılar');

  const DiscoverCategory(this.title);

  final String title;

  Future<List<AniListMedia>> load(
    AniListService service, {
    required int page,
    required int perPage,
  }) => switch (this) {
    DiscoverCategory.trending => service.getTrending(
      page: page,
      perPage: perPage,
    ),
    DiscoverCategory.popularManhwa => service.getPopularManhwa(
      page: page,
      perPage: perPage,
    ),
    DiscoverCategory.topRated => service.getTopRated(
      page: page,
      perPage: perPage,
    ),
  };
}

class CategorySeeAllScreen extends ConsumerStatefulWidget {
  const CategorySeeAllScreen({required this.category, super.key});

  final DiscoverCategory category;

  @override
  ConsumerState<CategorySeeAllScreen> createState() =>
      _CategorySeeAllScreenState();
}

class _CategorySeeAllScreenState extends ConsumerState<CategorySeeAllScreen> {
  static const int _pageSize = 30;

  final ScrollController _scrollController = ScrollController();
  final List<AniListMedia> _items = [];
  int _page = 1;
  bool _isLoading = false;
  bool _hasMore = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadNextPage());
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.extentAfter < 600) _loadNextPage();
  }

  Future<void> _loadNextPage() async {
    if (_isLoading || !_hasMore) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await widget.category.load(
        ref.read(aniListServiceProvider),
        page: _page,
        perPage: _pageSize,
      );
      if (!mounted) return;

      final knownIds = _items.map((item) => item.id).toSet();
      final newItems = response
          .where((item) => knownIds.add(item.id))
          .toList(growable: false);
      setState(() {
        _items.addAll(newItems);
        _page++;
        _hasMore = response.length == _pageSize && newItems.isNotEmpty;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(widget.category.title)),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_items.isEmpty && _isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_items.isEmpty && _error != null) {
      return _LoadError(onRetry: _loadNextPage);
    }
    if (_items.isEmpty && !_hasMore) {
      return const Center(
        child: Text(
          'Şu anda gösterilecek seri yok.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: _items.length + (_hasMore || _error != null ? 1 : 0),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisExtent: 270,
        crossAxisSpacing: 12,
        mainAxisSpacing: 16,
      ),
      itemBuilder: (context, index) {
        if (index >= _items.length) {
          if (_error != null) return _LoadError(onRetry: _loadNextPage);
          return const Center(
            child: SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        return _MediaGridCard(media: _items[index]);
      },
    );
  }
}

class _MediaGridCard extends StatelessWidget {
  const _MediaGridCard({required this.media});

  final AniListMedia media;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => SeriesDetailScreen(media: media),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox.expand(
                child: media.coverUrl.isEmpty
                    ? const _PosterPlaceholder()
                    : Image.network(
                        media.coverUrl,
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.low,
                        errorBuilder: (context, error, stackTrace) =>
                            const _PosterPlaceholder(),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            media.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.star_rounded, size: 14, color: AppColors.accent),
              const SizedBox(width: 3),
              Text(
                media.averageScore == null
                    ? '—'
                    : (media.averageScore! / 10).toStringAsFixed(1),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
              if (media.totalChapters != null) ...[
                const Spacer(),
                Flexible(
                  child: Text(
                    '${media.totalChapters} bölüm',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _PosterPlaceholder extends StatelessWidget {
  const _PosterPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.cardBackground,
      child: Center(
        child: Icon(
          Icons.broken_image_outlined,
          color: AppColors.textDisabled,
          size: 28,
        ),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 12),
            const Text(
              'Seriler yüklenemedi. Bağlantını kontrol edip tekrar dene.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Tekrar dene'),
            ),
          ],
        ),
      ),
    );
  }
}
