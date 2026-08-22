import 'dart:io';

import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;

import '../../core/constants/app_constants.dart';
import '../decoders/comic_decoder_factory.dart';
import '../models/comic_book.dart';
import 'archive_service.dart';

/// Kütüphane tarama orkestratörü.
///
/// Seçili klasördeki tüm desteklenen dosyaları bulur,
/// her biri için doğru decoder'ı [ComicDecoderFactory] aracılığıyla
/// oluşturur, Hive'a kaydeder ve kütüphane listesini döner.
class LibraryScannerService {
  final ArchiveService _archiveService;

  LibraryScannerService({ArchiveService? archiveService})
      : _archiveService = archiveService ?? const ArchiveService();

  // ─── Ana Tarama İşlemi ──────────────────────────────────────────────────────

  /// [folderPath] içindeki tüm desteklenen dosyaları tarar ve Hive'ı günceller.
  ///
  /// - Daha önce taranan dosyalar yeniden taranmaz (Hive'dan okunur).
  /// - Diskten silinmiş dosyalar Hive'dan temizlenir.
  /// - [onProgress] her dosya işlendiğinde (current, total) olarak çağrılır.
  Future<List<ComicBook>> scanFolder(
    String folderPath, {
    void Function(int current, int total)? onProgress,
  }) async {
    final box = Hive.box<ComicBook>(AppConstants.comicsBox);

    // 1. Diskteki desteklenen dosyaları bul
    final filePaths = _findSupportedFiles(folderPath);

    // 2. Diskten silinmiş dosyaları Hive'dan kaldır
    await _removeDeletedEntries(box, folderPath, filePaths);

    // 3. Her dosyayı sırayla işle
    final result = <ComicBook>[];

    for (int i = 0; i < filePaths.length; i++) {
      onProgress?.call(i + 1, filePaths.length);

      final filePath = filePaths[i];
      final id = _makeId(filePath);

      // Daha önce taranmışsa Hive'dan al
      final existing = box.get(id);
      if (existing != null) {
        result.add(existing);
        continue;
      }

      // Yeni dosya → formatına göre Isolate'ta (veya native async ile) tara
      final scanResult = await _archiveService.scanFile(filePath);

      if (scanResult.isValid) {
        final comic = ComicBook(
          id: id,
          title: scanResult.title,
          filePath: filePath,
          coverImageBytes: scanResult.coverImageBytes,
          totalPages: scanResult.totalPages,
          parentFolderPath: folderPath,
          addedAt: DateTime.now(),
        );
        await box.put(id, comic);
        result.add(comic);
      }
    }

    // Başlığa göre alfabetik sırala
    result.sort(
      (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    );

    return result;
  }

  // ─── Hive Okuma Yardımcıları ────────────────────────────────────────────────

  /// Hive'daki tüm kitapları başlığa göre sıralı döner.
  List<ComicBook> getAllComics() {
    final box = Hive.box<ComicBook>(AppConstants.comicsBox);
    return box.values.toList()
      ..sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  }

  /// Belirli bir klasöre ait kitapları başlığa göre sıralı döner.
  List<ComicBook> getComicsForFolder(String folderPath) {
    final box = Hive.box<ComicBook>(AppConstants.comicsBox);
    return box.values
        .where((c) => c.parentFolderPath == folderPath)
        .toList()
      ..sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  }

  // ─── Özel Yardımcılar ───────────────────────────────────────────────────────

  /// [folderPath] ve tüm alt klasörlerindeki desteklenen dosyaları sıralı döner.
  /// Desteklenen uzantılar: .cbz, .zip, .cbr, .rar, .pdf (büyük/küçük harf duyarsız)
  ///
  /// Recursive tarama: alt klasörlere de bakar (Manga/Cilt1/*.cbz vb.)
  /// Erişilemez dizinler/dosyalar sessizce atlanır.
  List<String> _findSupportedFiles(String folderPath) {
    final dir = Directory(folderPath);
    if (!dir.existsSync()) return [];

    final results = <String>[];
    _scanDirectory(dir, results);
    results.sort();
    return results;
  }

  /// [directory] içindirüksel olarak tarar.
  /// Her düzey try-catch ile korunur — bozuk/erişimsiz altın dizin tüm taramayı kesmez.
  void _scanDirectory(Directory directory, List<String> results) {
    Iterable<FileSystemEntity> entities;
    try {
      // followLinks:false – sembolik bağlantı döngülerini önler
      entities = directory.listSync(recursive: false, followLinks: false);
    } catch (_) {
      return; // Erişimsiz dizin → atla
    }

    for (final entity in entities) {
      try {
        if (entity is File) {
          if (ComicDecoderFactory.isSupported(entity.path)) {
            results.add(p.normalize(entity.path));
          }
        } else if (entity is Directory) {
          _scanDirectory(entity, results); // Alt klasöre in
        }
      } catch (_) {
        // Tek bir dosya/dizin hatası diğerlerini etkilemez
        continue;
      }
    }
  }

  /// Diskten silinen dosyaları Hive'dan temizler.
  Future<void> _removeDeletedEntries(
    Box<ComicBook> box,
    String folderPath,
    List<String> currentPaths,
  ) async {
    final currentPathSet = currentPaths.toSet();

    final keysToDelete = box.keys.where((key) {
      final comic = box.get(key);
      return comic != null &&
          comic.parentFolderPath == folderPath &&
          !currentPathSet.contains(comic.filePath);
    }).toList();

    for (final key in keysToDelete) {
      await box.delete(key);
    }
  }

  /// Dosya yolundan Hive key olarak kullanılacak tutarlı ID üretir.
  String _makeId(String filePath) => p.normalize(filePath);
}
