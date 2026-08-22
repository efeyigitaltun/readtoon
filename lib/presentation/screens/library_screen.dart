import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/comic_book.dart';
import '../providers/library_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/comic_cover_card.dart';
import 'reader_screen.dart';

/// Ana kütüphane ekranı.
/// Seçili klasördeki .cbz dosyalarını 3 sütunlu grid ile listeler.
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final libraryAsync = ref.watch(libraryProvider);
    final scanProgress = ref.watch(scanProgressProvider);
    final folderPath = ref.watch(selectedFolderProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(context, ref, folderPath, scanProgress),
      body: libraryAsync.when(
        loading: () => const _LoadingView(),
        error: (e, _) => _ErrorView(message: e.toString()),
        data: (comics) {
          if (comics.isEmpty) {
            return _EmptyLibraryView(
              isScanning: scanProgress.$2 > 0,
              onScan: () => ref.read(libraryProvider.notifier).scanLibrary(),
            );
          }
          return _ComicGrid(comics: comics);
        },
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    WidgetRef ref,
    String? folderPath,
    (int, int) scanProgress,
  ) {
    final isScanning = scanProgress.$2 > 0;

    return AppBar(
      title: const Text('Kütüphane'),
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

        // ─── Yenile / Tara Butonu ────────────────────────────────────────
        IconButton(
          tooltip: 'Klasörü yeniden tara',
          onPressed: isScanning
              ? null
              : () => ref.read(libraryProvider.notifier).scanLibrary(),
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

        // ─── Klasör Değiştir ─────────────────────────────────────────────
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded),
          onSelected: (value) async {
            if (value == 'change_folder') {
              final newPath =
                  await ref.read(selectedFolderProvider.notifier).pickFolder();
              if (newPath != null) {
                await ref
                    .read(libraryProvider.notifier)
                    .onFolderChanged(newPath);
              }
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'change_folder',
              child: Row(
                children: const [
                  Icon(Icons.folder_open_rounded,
                      size: 18, color: AppColors.textSecondary),
                  SizedBox(width: 10),
                  Text('Klasörü değiştir'),
                ],
              ),
            ),
            if (folderPath != null)
              PopupMenuItem(
                enabled: false,
                height: 36,
                child: Text(
                  folderPath,
                  style: const TextStyle(
                    color: AppColors.textDisabled,
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
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
// Grid
// ═══════════════════════════════════════════════════════════════════════════════

class _ComicGrid extends StatelessWidget {
  final List<ComicBook> comics;
  const _ComicGrid({required this.comics});

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
        );
      },
    );
  }

  void _openReader(BuildContext context, ComicBook comic) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReaderScreen(comic: comic),
      ),
    );
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
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: AppColors.error),
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
            Text(
              'Kütüphane Boş',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Seçili klasörde .cbz dosyası bulunamadı.\nFarklı bir klasör seçmeyi deneyin.',
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
