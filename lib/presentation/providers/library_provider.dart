import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../core/constants/app_constants.dart';
import '../../data/models/comic_book.dart';
import '../../data/models/folder_library_stats.dart';
import '../../data/models/read_history.dart';
import '../../data/services/archive_service.dart';
import '../../data/services/library_scanner_service.dart';
import '../../data/services/saf_file_access_service.dart';
import 'settings_provider.dart';

// ─── Servis Provider'ları ────────────────────────────────────────────────────

final archiveServiceProvider = Provider<ArchiveService>(
  (ref) => const ArchiveService(),
);

final libraryScannerServiceProvider = Provider<LibraryScannerService>(
  (ref) =>
      LibraryScannerService(archiveService: ref.read(archiveServiceProvider)),
);

// ─── Kütüphane Filtreleri ────────────────────────────────────────────────────

enum LibraryFilter { all, favorites, unread, read }

class LibraryFilterNotifier extends Notifier<LibraryFilter> {
  @override
  LibraryFilter build() => LibraryFilter.all;

  void select(LibraryFilter filter) => state = filter;
}

final libraryFilterProvider =
    NotifierProvider<LibraryFilterNotifier, LibraryFilter>(
      LibraryFilterNotifier.new,
    );

// ─── Tarama İlerlemesi ───────────────────────────────────────────────────────

/// Tarama sırasındaki ilerlemeyi tutar: (current, total). (0, 0) → tarama yok.
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

// ─── Tüm Lokasyonların Kütüphanesi ──────────────────────────────────────────

/// Hive'daki bütün kayıtlı lokasyonların kitaplarını yönetir.
/// Aktif klasör filtresi [visibleLibraryProvider] içinde uygulanır.
class LibraryNotifier extends AsyncNotifier<List<ComicBook>> {
  @override
  Future<List<ComicBook>> build() async {
    final settings = ref.read(appSettingsProvider);
    final folderPaths = settings.folderPaths;
    if (folderPaths.isEmpty) return const [];

    final scanner = ref.read(libraryScannerServiceProvider);
    if (settings.scanOnStartup) {
      final progressNotifier = ref.read(scanProgressProvider.notifier);
      try {
        for (final folderPath in folderPaths) {
          await scanner.scanFolder(
            folderPath,
            onProgress: progressNotifier.update,
          );
        }
      } finally {
        progressNotifier.reset();
      }
      ref.invalidate(folderLibraryStatsProvider);
    }

    return _loadComicsForFolders(folderPaths, scanner);
  }

  /// Seçili lokasyonu veya tüm kayıtlı lokasyonları yeniden tarar.
  Future<void> scanLibrary() async {
    final settings = ref.read(appSettingsProvider);
    final paths = settings.selectedFolderPath == null
        ? settings.folderPaths
        : <String>[settings.selectedFolderPath!];
    if (paths.isEmpty) return;

    final scanner = ref.read(libraryScannerServiceProvider);
    final progressNotifier = ref.read(scanProgressProvider.notifier);
    state = AsyncData(state.valueOrNull ?? const []);
    progressNotifier.reset();

    try {
      for (final path in paths) {
        await scanner.scanFolder(path, onProgress: progressNotifier.update);
      }
      state = AsyncData(
        _loadComicsForFolders(
          ref.read(appSettingsProvider).folderPaths,
          scanner,
        ),
      );
      ref.invalidate(folderLibraryStatsProvider);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    } finally {
      progressNotifier.reset();
    }
  }

  /// Belirtilen lokasyonu tarar; diğer lokasyonların kitaplarını korur.
  Future<void> scanFolder(String folderPath) async {
    final scanner = ref.read(libraryScannerServiceProvider);
    final progressNotifier = ref.read(scanProgressProvider.notifier);
    state = AsyncData(state.valueOrNull ?? const []);
    progressNotifier.reset();

    try {
      await scanner.scanFolder(folderPath, onProgress: progressNotifier.update);
      state = AsyncData(
        _loadComicsForFolders(
          ref.read(appSettingsProvider).folderPaths,
          scanner,
        ),
      );
      ref.invalidate(folderLibraryStatsProvider);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    } finally {
      progressNotifier.reset();
    }
  }

  /// Eski kurulum akışları için klasörü ekler, seçer ve tarar.
  Future<void> onFolderChanged(String newFolderPath) async {
    final settings = ref.read(appSettingsProvider.notifier);
    await settings.addFolderPath(newFolderPath);
    await settings.setSelectedFolderPath(newFolderPath);
    await scanFolder(newFolderPath);
  }

  /// Lokasyonu ve o lokasyona ait kitap/okuma geçmişi kayıtlarını kaldırır.
  Future<void> removeFolderPath(String folderPath) async {
    await ref.read(appSettingsProvider.notifier).removeFolderPath(folderPath);

    final comicsBox = Hive.box<ComicBook>(AppConstants.comicsBox);
    final comicIds = comicsBox.values
        .where((comic) => comic.parentFolderPath == folderPath)
        .map((comic) => comic.id)
        .toList();

    await comicsBox.deleteAll(comicIds);
    await Hive.box<ReadHistory>(AppConstants.historyBox).deleteAll(comicIds);

    state = AsyncData(
      _loadComicsForFolders(
        ref.read(appSettingsProvider).folderPaths,
        ref.read(libraryScannerServiceProvider),
      ),
    );
    ref.invalidate(folderLibraryStatsProvider);
  }

  /// Favori durumunu Hive'a kaydeder ve mevcut listeyi anında yeniler.
  Future<void> toggleFavorite(String comicId) async {
    final comic = Hive.box<ComicBook>(AppConstants.comicsBox).get(comicId);
    if (comic == null) return;
    await setFavorite(comicId, !comic.isFavorite);
  }

  Future<void> setFavorite(String comicId, bool isFavorite) async {
    final box = Hive.box<ComicBook>(AppConstants.comicsBox);
    final comic = box.get(comicId);
    if (comic == null) return;

    final previousValue = comic.isFavorite;
    comic.isFavorite = isFavorite;
    try {
      await box.put(comicId, comic);
    } catch (_) {
      comic.isFavorite = previousValue;
      rethrow;
    }

    state = state.whenData(
      (comics) =>
          comics.map((item) => item.id == comicId ? comic : item).toList(),
    );
  }

  /// Yerel kitabı AniList serisine bağlar veya bağlantısını kaldırır.
  Future<void> linkComic(String comicId, int? mediaId) async {
    final box = Hive.box<ComicBook>(AppConstants.comicsBox);
    final comic = box.get(comicId);
    if (comic == null) return;

    final previousMediaId = comic.linkedMediaId;
    comic.linkedMediaId = mediaId;
    try {
      await box.put(comicId, comic);
    } catch (_) {
      comic.linkedMediaId = previousMediaId;
      rethrow;
    }

    state = state.whenData(
      (comics) =>
          comics.map((item) => item.id == comicId ? comic : item).toList(),
    );
  }

  List<ComicBook> _loadComicsForFolders(
    List<String> folderPaths,
    LibraryScannerService scanner,
  ) {
    final comicsById = <String, ComicBook>{};
    for (final path in folderPaths) {
      for (final comic in scanner.getComicsForFolder(path)) {
        comicsById[comic.id] = comic;
      }
    }
    final comics = comicsById.values.toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return comics;
  }
}

final libraryProvider = AsyncNotifierProvider<LibraryNotifier, List<ComicBook>>(
  LibraryNotifier.new,
);

/// Seçili lokasyon filtresini uygulayan görünüm. null seçim tüm lokasyonlardır.
final visibleLibraryProvider = Provider<AsyncValue<List<ComicBook>>>((ref) {
  final library = ref.watch(libraryProvider);
  final selectedPath = ref.watch(
    appSettingsProvider.select((settings) => settings.selectedFolderPath),
  );
  if (selectedPath == null) return library;
  return library.whenData(
    (comics) => comics
        .where((comic) => comic.parentFolderPath == selectedPath)
        .toList(),
  );
});

// ─── Lokasyon İstatistikleri ────────────────────────────────────────────────

final _readHistoryChangesProvider = StreamProvider<void>((ref) async* {
  final box = Hive.box<ReadHistory>(AppConstants.historyBox);
  await for (final _ in box.watch()) {
    yield null;
  }
});

final folderLibraryStatsProvider =
    FutureProvider.autoDispose<List<FolderLibraryStats>>((ref) async {
      final folderPaths = ref.watch(
        appSettingsProvider.select((settings) => settings.folderPaths),
      );
      ref.watch(_readHistoryChangesProvider);

      final comicsBox = Hive.box<ComicBook>(AppConstants.comicsBox);
      final historyBox = Hive.box<ReadHistory>(AppConstants.historyBox);

      return Future.wait(
        folderPaths.map((path) async {
          final comics = comicsBox.values
              .where((comic) => comic.parentFolderPath == path)
              .toList();
          final readBooks = comics.where((comic) {
            return comic.readingStatus(historyBox.get(comic.id)) ==
                ComicReadingStatus.read;
          }).length;

          var totalBytes = 0;
          var seriesCount = 0;
          String? folderName;

          if (SafFileAccessService.isSafUri(path)) {
            final saf = SafFileAccessService();
            try {
              folderName = (await saf.stat(path))?.name;
              await for (final entry in saf.walk(path)) {
                if (!entry.file.isDir) totalBytes += entry.file.length;
              }
              seriesCount = (await saf.list(
                path,
              )).where((entry) => entry.isDir).length;
            } catch (_) {
              // A revoked grant leaves the cached book counts visible.
            }
          } else {
            final directory = Directory(path);
            try {
              await for (final entity in directory.list(
                recursive: true,
                followLinks: false,
              )) {
                if (entity is File) {
                  try {
                    totalBytes += (await entity.stat()).size;
                  } catch (_) {
                    // Erişilemeyen tek bir dosya toplam boyutu engellemesin.
                  }
                }
              }
            } catch (_) {
              // Silinmiş/erişilemeyen klasör için boyut sıfır gösterilir.
            }

            try {
              await for (final entity in directory.list(followLinks: false)) {
                if (entity is Directory) seriesCount++;
              }
            } catch (_) {
              // Klasör listelenemiyorsa seri sayısı sıfır kalır.
            }
          }

          return FolderLibraryStats(
            folderPath: path,
            folderNameOverride: folderName,
            totalBooks: comics.length,
            totalBytes: totalBytes,
            seriesCount: seriesCount,
            readBooks: readBooks,
            unreadBooks: comics.length - readBooks,
          );
        }),
      );
    });

// ─── Okuma Geçmişi Provider'ı ────────────────────────────────────────────────

/// Bir kitabın okuma geçmişini döner. null → bu kitap hiç açılmamış.
final readHistoryProvider = StreamProvider.family<ReadHistory?, String>((
  ref,
  comicId,
) async* {
  final box = Hive.box<ReadHistory>(AppConstants.historyBox);
  yield box.get(comicId);

  await for (final _ in box.watch(key: comicId)) {
    yield box.get(comicId);
  }
});

/// Belirli bir kitabın ilerleme oranını döner (0.0–1.0).
final comicProgressProvider = Provider.family<double, ComicBook>((ref, comic) {
  final history = ref.watch(readHistoryProvider(comic.id)).valueOrNull;
  if (history == null || comic.totalPages == 0) return 0.0;
  return history.progressOf(comic.totalPages);
});
