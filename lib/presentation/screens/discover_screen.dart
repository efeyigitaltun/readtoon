import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/anilist_media.dart';
import '../providers/discover_provider.dart';
import '../widgets/shimmer_loading.dart';
import 'category_see_all_screen.dart';
import 'series_detail_screen.dart';

class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  String _query = '';
  String _debouncedQuery = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() => _query = value);
    _debounce?.cancel();

    final normalizedQuery = value.trim();
    if (normalizedQuery.isEmpty) {
      setState(() => _debouncedQuery = '');
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _debouncedQuery = normalizedQuery);
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _onSearchChanged('');
  }

  void _invalidateShowcases() {
    ref
      ..invalidate(trendingMangaProvider)
      ..invalidate(popularManhwaProvider)
      ..invalidate(topRatedMangaProvider);
  }

  @override
  Widget build(BuildContext context) {
    final isSearching = _query.trim().isNotEmpty;
    final trendingMedia = ref.watch(trendingMangaProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Keşfet'),
        actions: [
          IconButton(
            tooltip: 'Vitrinleri yenile',
            onPressed: _invalidateShowcases,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: CustomScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              child: _SearchField(
                controller: _searchController,
                hasQuery: isSearching,
                onChanged: _onSearchChanged,
                onClear: _clearSearch,
              ),
            ),
          ),
          if (isSearching) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  _debouncedQuery.isEmpty
                      ? 'Aranıyor...'
                      : '"$_debouncedQuery" için sonuçlar',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            if (_debouncedQuery.isEmpty)
              _buildSearchLoadingSliver()
            else
              ..._buildSearchSlivers(
                context,
                ref.watch(mangaSearchProvider(_debouncedQuery)),
              ),
          ] else ...[
            SliverToBoxAdapter(child: _DiscoverSpotlight(media: trendingMedia)),
            SliverToBoxAdapter(
              child: _ShowcaseSection(
                title: 'Trend Olanlar',
                subtitle: 'Şu sıralar konuşulan seriler',
                media: trendingMedia,
                onSeeAll: () => _openCategory(DiscoverCategory.trending),
                onRetry: () => ref.invalidate(trendingMangaProvider),
              ),
            ),
            SliverToBoxAdapter(
              child: _ShowcaseSection(
                title: 'Popüler Manhwalar',
                subtitle: 'Güney Kore çıkışlı popüler seriler',
                media: ref.watch(popularManhwaProvider),
                onSeeAll: () => _openCategory(DiscoverCategory.popularManhwa),
                onRetry: () => ref.invalidate(popularManhwaProvider),
              ),
            ),
            SliverToBoxAdapter(
              child: _ShowcaseSection(
                title: 'En Yüksek Puanlılar',
                subtitle: 'AniList puanına göre öne çıkanlar',
                media: ref.watch(topRatedMangaProvider),
                onSeeAll: () => _openCategory(DiscoverCategory.topRated),
                onRetry: () => ref.invalidate(topRatedMangaProvider),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchLoadingSliver() {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      sliver: SliverGrid(
        delegate: SliverChildBuilderDelegate(
          (context, index) => const _SearchPosterSkeleton(),
          childCount: 6,
        ),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisExtent: 310,
          crossAxisSpacing: 12,
          mainAxisSpacing: 16,
        ),
      ),
    );
  }

  void _openCategory(DiscoverCategory category) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => CategorySeeAllScreen(category: category),
      ),
    );
  }

  List<Widget> _buildSearchSlivers(
    BuildContext context,
    AsyncValue<List<AniListMedia>> search,
  ) {
    return search.when(
      loading: () => [_buildSearchLoadingSliver()],
      error: (error, _) => [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _SearchMessage(
            icon: Icons.cloud_off_outlined,
            title: 'Arama yapılamadı',
            message: 'Bağlantını kontrol edip yeniden deneyebilirsin.',
            actionLabel: 'Tekrar dene',
            onAction: () =>
                ref.invalidate(mangaSearchProvider(_debouncedQuery)),
          ),
        ),
      ],
      data: (results) {
        if (results.isEmpty) {
          return const [
            SliverFillRemaining(
              hasScrollBody: false,
              child: _SearchMessage(
                icon: Icons.search_off_rounded,
                title: 'Sonuç bulunamadı',
                message: 'Başka bir manga adıyla tekrar deneyebilirsin.',
              ),
            ),
          ];
        }

        return [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            sliver: SliverGrid(
              delegate: SliverChildBuilderDelegate(
                (context, index) => _MediaPosterCard(media: results[index]),
                childCount: results.length,
              ),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisExtent: 310,
                crossAxisSpacing: 12,
                mainAxisSpacing: 16,
              ),
            ),
          ),
        ];
      },
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.hasQuery,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final bool hasQuery;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: 'Manga, manhwa veya manhua ara',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: hasQuery
            ? IconButton(
                tooltip: 'Aramayı temizle',
                onPressed: onClear,
                icon: const Icon(Icons.close_rounded),
              )
            : null,
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _DiscoverSpotlight extends StatelessWidget {
  const _DiscoverSpotlight({required this.media});

  final AsyncValue<List<AniListMedia>> media;

  @override
  Widget build(BuildContext context) {
    return media.when(
      loading: () => const Padding(
        padding: EdgeInsets.fromLTRB(16, 4, 16, 28),
        child: _SpotlightSkeleton(),
      ),
      error: (error, stackTrace) => const SizedBox.shrink(),
      data: (items) => items.isEmpty
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
              child: _SpotlightCard(media: items.first),
            ),
    );
  }
}

class _SpotlightCard extends StatelessWidget {
  const _SpotlightCard({required this.media});

  final AniListMedia media;

  @override
  Widget build(BuildContext context) {
    final imageUrl = media.bannerUrl?.isNotEmpty == true
        ? media.bannerUrl!
        : media.coverUrl;
    final score = media.averageScore == null
        ? '—'
        : (media.averageScore! / 10).toStringAsFixed(1);
    final descriptor = media.genres.take(2).join(' · ');

    return Semantics(
      button: true,
      label: 'Öne çıkan seri: ${media.title}',
      child: Material(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => SeriesDetailScreen(media: media),
            ),
          ),
          child: SizedBox(
            height: 316,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (imageUrl.isEmpty)
                  const _SpotlightBackdrop()
                else
                  ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(sigmaX: 1.5, sigmaY: 1.5),
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      cacheWidth: 1100,
                      filterQuality: FilterQuality.low,
                      loadingBuilder: (context, child, progress) =>
                          progress == null
                          ? child
                          : const ShimmerLoading(
                              child: ColoredBox(color: AppColors.shimmerBase),
                            ),
                      errorBuilder: (context, error, stackTrace) =>
                          const _SpotlightBackdrop(),
                    ),
                  ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x33000000),
                        Color(0x66000000),
                        Color(0xF2121212),
                      ],
                      stops: [0, 0.42, 1],
                    ),
                  ),
                ),
                Positioned(
                  top: 16,
                  left: 16,
                  child: _GlassLabel(
                    icon: Icons.auto_awesome_rounded,
                    label: 'ÖNE ÇIKAN SERİ',
                  ),
                ),
                Positioned(
                  top: 16,
                  right: 16,
                  child: _GlassLabel(
                    icon: Icons.star_rounded,
                    label: score,
                    accent: true,
                  ),
                ),
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 20,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        media.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              color: AppColors.textPrimary,
                              fontSize: 27,
                              height: 1.1,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        descriptor.isEmpty
                            ? _statusLabel(media.status)
                            : descriptor,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 15),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.accent,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Seriyi keşfet',
                                  style: TextStyle(
                                    color: AppColors.background,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                                SizedBox(width: 6),
                                Icon(
                                  Icons.arrow_forward_rounded,
                                  color: AppColors.background,
                                  size: 16,
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          if (media.totalChapters != null)
                            Text(
                              '${media.totalChapters} bölüm',
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
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
      ),
    );
  }
}

String _statusLabel(String? status) => switch (status) {
  'RELEASING' => 'Devam ediyor',
  'FINISHED' => 'Tamamlandı',
  'NOT_YET_RELEASED' => 'Yakında',
  'HIATUS' => 'Ara verildi',
  _ => 'AniList seçkisi',
};

class _GlassLabel extends StatelessWidget {
  const _GlassLabel({
    required this.icon,
    required this.label,
    this.accent = false,
  });

  final IconData icon;
  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final foreground = accent ? AppColors.accent : AppColors.textPrimary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foreground),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: foreground,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _SpotlightBackdrop extends StatelessWidget {
  const _SpotlightBackdrop();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.topRight,
          radius: 1.4,
          colors: [Color(0xFF33454B), AppColors.cardBackground],
        ),
      ),
    );
  }
}

class _SpotlightSkeleton extends StatelessWidget {
  const _SpotlightSkeleton();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: SizedBox(
        height: 316,
        child: ShimmerLoading(
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: AppColors.shimmerBase),
              Positioned(
                top: 16,
                left: 16,
                child: ShimmerBlock(width: 116, height: 28, borderRadius: 20),
              ),
              Positioned(
                top: 16,
                right: 16,
                child: ShimmerBlock(width: 54, height: 28, borderRadius: 20),
              ),
              Positioned(
                left: 20,
                right: 20,
                bottom: 20,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShimmerBlock(width: 210, height: 24, borderRadius: 8),
                    const SizedBox(height: 9),
                    ShimmerBlock(width: 140, height: 12, borderRadius: 6),
                    const SizedBox(height: 16),
                    ShimmerBlock(width: 132, height: 38, borderRadius: 24),
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

class _ShowcaseSkeleton extends StatelessWidget {
  const _ShowcaseSkeleton();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 270,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: 3,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) =>
            const SizedBox(width: 142, child: _ShowcasePosterSkeleton()),
      ),
    );
  }
}

class _ShowcasePosterSkeleton extends StatelessWidget {
  const _ShowcasePosterSkeleton();

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Expanded(child: ShimmerBlock(borderRadius: 12)),
          const SizedBox(height: 9),
          const ShimmerBlock(width: 116, height: 13, borderRadius: 6),
          const SizedBox(height: 7),
          Row(
            children: const [
              ShimmerBlock(width: 48, height: 11, borderRadius: 6),
              SizedBox(width: 10),
              ShimmerBlock(width: 62, height: 11, borderRadius: 6),
            ],
          ),
        ],
      ),
    );
  }
}

class _SearchPosterSkeleton extends StatelessWidget {
  const _SearchPosterSkeleton();

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Expanded(child: ShimmerBlock(borderRadius: 14)),
          const SizedBox(height: 10),
          const ShimmerBlock(width: 150, height: 14, borderRadius: 6),
          const SizedBox(height: 8),
          const Row(
            children: [
              ShimmerBlock(width: 48, height: 12, borderRadius: 6),
              SizedBox(width: 12),
              ShimmerBlock(width: 70, height: 12, borderRadius: 6),
            ],
          ),
        ],
      ),
    );
  }
}

class _ShowcaseSection extends StatelessWidget {
  const _ShowcaseSection({
    required this.title,
    required this.subtitle,
    required this.media,
    required this.onSeeAll,
    required this.onRetry,
  });

  final String title;
  final String subtitle;
  final AsyncValue<List<AniListMedia>> media;
  final VoidCallback onSeeAll;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Tümünü gör: $title',
                  onPressed: onSeeAll,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
          ),
          media.when(
            loading: () => const _ShowcaseSkeleton(),
            error: (error, _) => _SectionError(onRetry: onRetry),
            data: (items) {
              if (items.isEmpty) {
                return const SizedBox(
                  height: 120,
                  child: Center(
                    child: Text(
                      'Şu anda gösterilecek seri yok.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                );
              }
              return SizedBox(
                height: 270,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: items.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 12),
                  itemBuilder: (context, index) => SizedBox(
                    width: 142,
                    child: _MediaPosterCard(media: items[index]),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SectionError extends StatelessWidget {
  const _SectionError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 140,
      child: Center(
        child: TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Yüklenemedi, tekrar dene'),
        ),
      ),
    );
  }
}

class _MediaPosterCard extends StatelessWidget {
  const _MediaPosterCard({required this.media});

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
                        cacheWidth: 480,
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return const _PosterPlaceholder(loading: true);
                        },
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
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.star_rounded, size: 16, color: AppColors.accent),
              const SizedBox(width: 4),
              Text(
                media.averageScore == null
                    ? 'Puan yok'
                    : (media.averageScore! / 10).toStringAsFixed(1),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              if (media.totalChapters != null) ...[
                const SizedBox(width: 8),
                const Icon(
                  Icons.menu_book_rounded,
                  size: 14,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    '${media.totalChapters} bölüm',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
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
  const _PosterPlaceholder({this.loading = false});

  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const ShimmerLoading(
        child: ColoredBox(color: AppColors.shimmerBase),
      );
    }
    return const ColoredBox(
      color: AppColors.cardBackground,
      child: Center(
        child: Icon(
          Icons.broken_image_outlined,
          color: AppColors.textDisabled,
          size: 32,
        ),
      ),
    );
  }
}

class _SearchMessage extends StatelessWidget {
  const _SearchMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppColors.textSecondary),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              TextButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
