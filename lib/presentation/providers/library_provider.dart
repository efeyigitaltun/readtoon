import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/comic_book.dart';
import '../../data/models/read_history.dart';
import '../../data/services/archive_service.dart';
import '../../data/services/library_scanner_service.dart';
import '../../core/constants/app_constants.dart';
import 'settings_provider.dart';
import 'package:hive/hive.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Servis Provider'ları
// ═══════════════════════════════════════════════════════════════════════════════

final archiveServiceProvider = Provider<ArchiveService>(
  (ref) => const ArchiveService(),
);

final libraryScannerServiceProvider = Provider<LibraryScannerService>(
  (ref) =>
      LibraryScannerService(archiveService: ref.read(archiveServiceProvider)),
);

// ═══════════════════════════════════════════════════════════════════════════════
// Tarama İlerleme State'i
// ═══════════════════════════════════════════════════════════════════════════════

/// Tarama sırasındaki ilerlemeyi tutar: (current, total).
/// (0, 0) → tarama yok.
class ScanProgressNotifier extends Notifier<(int, int)> {
  @override
  (int, int) build() => (0, 0);

  void update(int current, int total) => state = (current, total);
  void reset() => state = (0, 0);
  bool get isScanning => state.$2 > 0;
}

final scanProgressProvider = NotifierProvider<ScanProgressNotifier, (int, int)>(
  ScanProgressNotifier.new,
);

// ═══════════════════════════════════════════════════════════════════════════════
// Kütüphane State'i
// ═══════════════════════════════════════════════════════════════════════════════

/// Kütüphanedeki manga listesini yönetir.
/// Tarama işlemini başlatır, ilerlemesini takip eder, sonuçları saklar.
class LibraryNotifier extends AsyncNotifier<List<ComicBook>> {
  @override
  Future<List<ComicBook>> build() async {
    final scanner = ref.read(libraryScannerServiceProvider);
    final settings = ref.read(appSettingsProvider);
    final folderPath = settings.folderPath;

    if (folderPath == null) return [];

    if (settings.scanOnStartup) {
      final progressNotifier = ref.read(scanProgressProvider.notifier);
      try {
        return await scanner.scanFolder(
          folderPath,
          onProgress: progressNotifier.update,
        );
      } finally {
        progressNotifier.reset();
      }
    }

    // Otomatik tarama kapalıysa Hive'daki son kütüphane verisini göster.
    return scanner.getComicsForFolder(folderPath);
  }

  /// Seçili klasörü tarar ve kütüphaneyi yeniler.
  Future<void> scanLibrary() async {
    final folderPath = ref.read(appSettingsProvider).folderPath;
    if (folderPath == null) return;

    final scanner = ref.read(libraryScannerServiceProvider);
    final progressNotifier = ref.read(scanProgressProvider.notifier);

    // Tarama sırasında mevcut listeyi koru (yükleniyor animasyonu yerine)
    final currentList = state.valueOrNull ?? [];
    state = AsyncData(currentList); // önceki listeyi göster

    progressNotifier.reset();

    try {
      final comics = await scanner.scanFolder(
        folderPath,
        onProgress: (current, total) {
          progressNotifier.update(current, total);
        },
      );

      state = AsyncData(comics);
    } catch (e, st) {
      state = AsyncError(e, st);
    } finally {
      progressNotifier.reset();
    }
  }

  /// Yeni bir klasör seçildiğinde kütüphaneyi o klasöre göre yeniler.
  Future<void> onFolderChanged(String newFolderPath) async {
    final scanner = ref.read(libraryScannerServiceProvider);

    state = const AsyncLoading();

    try {
      final comics = await scanner.scanFolder(newFolderPath);
      state = AsyncData(comics);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }
}

final libraryProvider = AsyncNotifierProvider<LibraryNotifier, List<ComicBook>>(
  LibraryNotifier.new,
);

// ═══════════════════════════════════════════════════════════════════════════════
// Okuma Geçmişi Provider'ı
// ═══════════════════════════════════════════════════════════════════════════════

/// Bir kitabın okuma geçmişini döner.
/// [null] → bu kitap hiç açılmamış.
final readHistoryProvider = Provider.family<ReadHistory?, String>((
  ref,
  comicId,
) {
  final box = Hive.box<ReadHistory>(AppConstants.historyBox);
  return box.get(comicId);
});

// ─── İlerleme yüzdesi kısayolu ────────────────────────────────────────────────

/// Belirli bir kitabın ilerleme oranını döner (0.0 – 1.0).
final comicProgressProvider = Provider.family<double, ComicBook>((ref, comic) {
  final history = ref.watch(readHistoryProvider(comic.id));
  if (history == null || comic.totalPages == 0) return 0.0;
  return history.progressOf(comic.totalPages);
});
