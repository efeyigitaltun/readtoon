import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/comic_book.dart';
import '../../data/models/folder_library_stats.dart';
import '../../data/models/tracked_series.dart';
import '../providers/auth_provider.dart';
import '../providers/library_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/tracked_series_provider.dart';
import '../widgets/comic_cover_card.dart';
import '../widgets/locations_management_section.dart';
import '../widgets/link_comic_sheet.dart';
import 'auth_screen.dart';
import 'reader_screen.dart';
import 'settings_screen.dart';

/// Ana kütüphane ekranı.
/// Seçili klasördeki .cbz dosyalarını 3 sütunlu grid ile listeler.
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  /// Seçili klasörü veya tüm lokasyonları SAF erişim izniyle yeniden tarar.
  Future<void> _scanWithPermissionCheck(
    BuildContext context,
    WidgetRef ref,
  ) async {
    try {
      await ref.read(libraryProvider.notifier).scanLibrary();
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Kütüphane taranamadı: $error')));
      }
    }
  }

  Future<bool> _requireSignIn(BuildContext context, WidgetRef ref) async {
    var user = ref.read(authStateProvider).valueOrNull;
    if (user == null && ref.read(authStateProvider).isLoading) {
      try {
        user = await ref.read(authStateProvider.future);
      } catch (_) {
        user = null;
      }
    }
    if (user != null) return true;
    if (!context.mounted) return false;

    final didSignIn = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute<bool>(builder: (_) => const AuthScreen()));
    return context.mounted &&
        (ref.read(authStateProvider).valueOrNull != null ||
            (didSignIn == true && !ref.read(guestModeProvider)));
  }

  Future<void> _toggleFavorite(
    BuildContext context,
    WidgetRef ref,
    ComicBook comic,
  ) async {
    if (!await _requireSignIn(context, ref)) return;
    try {
      final mediaId = comic.linkedMediaId;
      final trackedNotifier = ref.read(trackedSeriesProvider.notifier);
      final tracked = mediaId == null
          ? null
          : trackedNotifier.findByMediaId(mediaId);
      final nextFavorite = !(tracked?.isFavorite ?? comic.isFavorite);
      await ref
          .read(libraryProvider.notifier)
          .setFavorite(comic.id, nextFavorite);
      if (mediaId != null) {
        final series =
            tracked ??
            TrackedSeries(mediaId: mediaId, title: comic.title, coverUrl: '');
        series.isFavorite = nextFavorite;
        await trackedNotifier.save(series);
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Favori değişikliği kaydedilemedi.')),
        );
      }
    }
  }

  Future<void> _showLinkComicSheet(
    BuildContext context,
    WidgetRef ref,
    ComicBook comic,
  ) async {
    final series = ref.read(trackedSeriesProvider);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => LinkComicSheet(
        comic: comic,
        series: series,
        onSelected: (mediaId) async {
          try {
            await ref
                .read(libraryProvider.notifier)
                .linkComic(comic.id, mediaId);
            if (!sheetContext.mounted) return;
            Navigator.of(sheetContext).pop();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    mediaId == null
                        ? 'Seri eşleşmesi kaldırıldı.'
                        : 'Yerel dosya takip serisiyle eşleştirildi.',
                  ),
                ),
              );
            }
          } catch (_) {
            if (sheetContext.mounted) {
              ScaffoldMessenger.of(sheetContext).showSnackBar(
                const SnackBar(content: Text('Eşleştirme kaydedilemedi.')),
              );
            }
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final libraryAsync = ref.watch(visibleLibraryProvider);
    final scanProgress = ref.watch(scanProgressProvider);
    final selectedFolderPath = ref.watch(
      appSettingsProvider.select((settings) => settings.selectedFolderPath),
    );
    final activeFilter = ref.watch(libraryFilterProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(context, ref, selectedFolderPath, scanProgress),
      body: Column(
        children: [
          const LocationsManagementSection(),
          _LibraryFilterBar(
            selected: activeFilter,
            onSelected: (filter) =>
                ref.read(libraryFilterProvider.notifier).select(filter),
          ),
          Expanded(
            child: libraryAsync.when(
              loading: () => const _LoadingView(),
              error: (e, _) => _ErrorView(message: e.toString()),
              data: (comics) {
                if (comics.isEmpty) {
                  return _EmptyLibraryView(
                    isScanning: scanProgress.$2 > 0,
                    onScan: () =>
                        ref.read(libraryProvider.notifier).scanLibrary(),
                  );
                }

                final visibleComics = _filterComics(ref, comics, activeFilter);
                if (visibleComics.isEmpty) {
                  return _EmptyFilterView(
                    filter: activeFilter,
                    onReset: () => ref
                        .read(libraryFilterProvider.notifier)
                        .select(LibraryFilter.all),
                  );
                }
                return _ComicGrid(
                  comics: visibleComics,
                  onLink: (comic) => _showLinkComicSheet(context, ref, comic),
                  onToggleFavorite: (comic) =>
                      _toggleFavorite(context, ref, comic),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<ComicBook> _filterComics(
    WidgetRef ref,
    List<ComicBook> comics,
    LibraryFilter filter,
  ) {
    switch (filter) {
      case LibraryFilter.all:
        return comics;
      case LibraryFilter.favorites:
        final tracked = ref.watch(trackedSeriesProvider);
        return comics.where((comic) {
          final mediaId = comic.linkedMediaId;
          if (mediaId == null) return comic.isFavorite;
          for (final series in tracked) {
            if (series.mediaId == mediaId) return series.isFavorite;
          }
          return comic.isFavorite;
        }).toList();
      case LibraryFilter.unread:
        return comics.where((comic) {
          final history = ref.watch(readHistoryProvider(comic.id)).valueOrNull;
          return comic.readingStatus(history) == ComicReadingStatus.unread;
        }).toList();
      case LibraryFilter.read:
        return comics.where((comic) {
          final history = ref.watch(readHistoryProvider(comic.id)).valueOrNull;
          return comic.readingStatus(history) == ComicReadingStatus.read;
        }).toList();
    }
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    WidgetRef ref,
    String? selectedFolderPath,
    (int, int) scanProgress,
  ) {
    final isScanning = scanProgress.$2 > 0;

    return AppBar(
      title: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: selectedFolderPath == null
            ? null
            : () => ref
                  .read(appSettingsProvider.notifier)
                  .setSelectedFolderPath(null),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              selectedFolderPath == null
                  ? 'Kütüphane'
                  : FolderLibraryStats.nameFromPath(selectedFolderPath),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            if (selectedFolderPath != null)
              const Text(
                'Tüm klasörlere dön',
                style: TextStyle(color: AppColors.accent, fontSize: 11),
              ),
          ],
        ),
      ),
      actions: [
        // ─── Tarama İlerleme Göstergesi ─────────────────────────────────
        if (isScanning)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: Text(
                '${scanProgress.$1}/${scanProgress.$2}',
                style: const TextStyle(
                  color: AppColors.accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),

        // ─── Yenile / Tara Butonu ──────────────────────────────────────────
        IconButton(
          tooltip: 'Klasörü yeniden tara',
          onPressed: isScanning
              ? null
              : () => _scanWithPermissionCheck(context, ref),
          icon: isScanning
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.accent,
                  ),
                )
              : const Icon(Icons.refresh_rounded),
        ),

        IconButton(
          tooltip: 'Ayarlar',
          icon: const Icon(Icons.settings_rounded),
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            );
          },
        ),
      ],
      bottom: isScanning
          ? PreferredSize(
              preferredSize: const Size.fromHeight(3),
              child: LinearProgressIndicator(
                value: scanProgress.$2 > 0
                    ? scanProgress.$1 / scanProgress.$2
                    : null,
                backgroundColor: AppColors.divider,
                color: AppColors.accent,
                minHeight: 3,
              ),
            )
          : null,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Filtre Sekmeleri
// ═══════════════════════════════════════════════════════════════════════════════

class _LibraryFilterBar extends StatelessWidget {
  final LibraryFilter selected;
  final ValueChanged<LibraryFilter> onSelected;

  const _LibraryFilterBar({required this.selected, required this.onSelected});

  static const _filters = <(LibraryFilter, String)>[
    (LibraryFilter.all, 'Tümü'),
    (LibraryFilter.favorites, 'Favoriler'),
    (LibraryFilter.unread, 'Okunmayanlar'),
    (LibraryFilter.read, 'Okunanlar'),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            for (var index = 0; index < _filters.length; index++) ...[
              if (index > 0) const SizedBox(width: 8),
              _buildChip(_filters[index].$1, _filters[index].$2),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildChip(LibraryFilter filter, String label) {
    final isSelected = selected == filter;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      showCheckmark: false,
      onSelected: (_) => onSelected(filter),
      backgroundColor: AppColors.surface,
      selectedColor: AppColors.accent,
      side: BorderSide(
        color: isSelected ? AppColors.accent : AppColors.divider,
      ),
      labelStyle: TextStyle(
        color: isSelected ? AppColors.background : AppColors.textSecondary,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
      ),
    );
  }
}

class _EmptyFilterView extends StatelessWidget {
  final LibraryFilter filter;
  final VoidCallback onReset;

  const _EmptyFilterView({required this.filter, required this.onReset});

  @override
  Widget build(BuildContext context) {
    final (icon, title, message) = switch (filter) {
      LibraryFilter.all => (
        Icons.menu_book_rounded,
        'Kütüphane boş',
        'Henüz kitap eklenmemiş.',
      ),
      LibraryFilter.favorites => (
        Icons.favorite_border_rounded,
        'Favori yok',
        'Favori kitaplarını burada göreceksin.',
      ),
      LibraryFilter.unread => (
        Icons.mark_email_read_outlined,
        'Okunmamış kitap yok',
        'Kütüphanendeki kitapların tümü okunmuş.',
      ),
      LibraryFilter.read => (
        Icons.menu_book_rounded,
        'Okunmuş kitap yok',
        'Bir kitabı bitirdiğinde burada görünecek.',
      ),
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: AppColors.textDisabled),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: onReset,
              child: const Text('Tüm kitapları göster'),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Grid
// ═══════════════════════════════════════════════════════════════════════════════

class _ComicGrid extends StatelessWidget {
  final List<ComicBook> comics;
  final ValueChanged<ComicBook> onLink;
  final ValueChanged<ComicBook> onToggleFavorite;

  const _ComicGrid({
    required this.comics,
    required this.onLink,
    required this.onToggleFavorite,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(AppConstants.gridPadding),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: AppConstants.gridCrossAxisCount,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.62, // Dikey kart oranı (kapak + başlık)
      ),
      itemCount: comics.length,
      itemBuilder: (context, index) {
        final comic = comics[index];
        return ComicCoverCard(
          comic: comic,
          onTap: () => _openReader(context, comic),
          onLongPress: () => onLink(comic),
          onToggleFavorite: () => onToggleFavorite(comic),
        );
      },
    );
  }

  void _openReader(BuildContext context, ComicBook comic) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => ReaderScreen(comic: comic)));
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Durum Görünümleri
// ═══════════════════════════════════════════════════════════════════════════════

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(color: AppColors.accent),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  const _ErrorView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: AppColors.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Bir hata oluştu',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: AppColors.error),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyLibraryView extends StatelessWidget {
  final bool isScanning;
  final VoidCallback onScan;

  const _EmptyLibraryView({required this.isScanning, required this.onScan});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.inbox_rounded,
              size: 64,
              color: AppColors.textDisabled,
            ),
            const SizedBox(height: 16),
            Text('Kütüphane Boş', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Seçili klasörde desteklenen manga dosyası bulunamadı.\n'
              'Farklı bir klasör seçmeyi deneyin.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            if (!isScanning)
              OutlinedButton.icon(
                onPressed: onScan,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Yeniden Tara'),
              ),
          ],
        ),
      ),
    );
  }
}
