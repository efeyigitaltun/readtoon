import 'dart:io';

import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;

import '../../core/constants/app_constants.dart';
import '../decoders/comic_decoder_factory.dart';
import '../models/comic_book.dart';
import 'archive_service.dart';
import 'saf_file_access_service.dart';

/// Kütüphane tarama orkestratörü.
///
/// Seçili klasördeki tüm desteklenen dosyaları bulur,
/// her biri için doğru decoder'ı [ComicDecoderFactory] aracılığıyla
/// oluşturur, Hive'a kaydeder ve kütüphane listesini döner.
class LibraryScannerService {
  final ArchiveService _archiveService;
  final SafFileAccessService _safFileAccessService;

  LibraryScannerService({
    ArchiveService? archiveService,
    SafFileAccessService? safFileAccessService,
  }) : _archiveService = archiveService ?? const ArchiveService(),
       _safFileAccessService = safFileAccessService ?? SafFileAccessService();

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
    final files = await _findSupportedFiles(folderPath);
    final filePaths = files.map((file) => file.path).toList(growable: false);

    // 2. Diskten silinmiş dosyaları Hive'dan kaldır
    await _removeDeletedEntries(box, folderPath, filePaths);

    // 3. Her dosyayı sırayla işle
    final result = <ComicBook>[];

    for (int i = 0; i < filePaths.length; i++) {
      onProgress?.call(i + 1, filePaths.length);

      final file = files[i];
      final filePath = file.path;
      final id = _makeId(filePath);

      // Daha önce taranmışsa Hive'dan al
      final existing = box.get(id);
      if (existing != null) {
        result.add(existing);
        continue;
      }

      // Yeni dosya → formatına göre Isolate'ta (veya native async ile) tara
      final scanResult = await _archiveService.scanFile(
        filePath,
        displayName: file.name,
      );

      if (scanResult.isValid) {
        final comic = ComicBook(
          id: id,
          title: scanResult.title,
          filePath: filePath,
          sourceFileName: file.name,
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
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  }

  /// Belirli bir klasöre ait kitapları başlığa göre sıralı döner.
  List<ComicBook> getComicsForFolder(String folderPath) {
    final box = Hive.box<ComicBook>(AppConstants.comicsBox);
    return box.values.where((c) => c.parentFolderPath == folderPath).toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  }

  // ─── Özel Yardımcılar ───────────────────────────────────────────────────────

  /// [folderPath] ve tüm alt klasörlerindeki desteklenen dosyaları sıralı döner.
  /// Desteklenen uzantılar: .cbz, .zip, .cbr, .rar, .pdf (büyük/küçük harf duyarsız)
  ///
  /// Recursive tarama: alt klasörlere de bakar (Manga/Cilt1/*.cbz vb.)
  /// Erişilemez dizinler/dosyalar sessizce atlanır.
  Future<List<_ComicFileReference>> _findSupportedFiles(
    String folderPath,
  ) async {
    if (SafFileAccessService.isSafUri(folderPath)) {
      final results = <_ComicFileReference>[];
      try {
        await for (final entry in _safFileAccessService.walk(folderPath)) {
          final file = entry.file;
          if (!file.isDir && ComicDecoderFactory.isSupported(file.name)) {
            results.add(_ComicFileReference(path: file.uri, name: file.name));
          }
        }
      } catch (_) {
        // Do not interpret a revoked SAF grant as an empty folder and delete cache.
        rethrow;
      }
      results.sort((a, b) => a.path.compareTo(b.path));
      return results;
    }

    final dir = Directory(folderPath);
    if (!dir.existsSync()) {
      throw FileSystemException('Klasöre erişilemiyor.', folderPath);
    }

    final results = <_ComicFileReference>[];
    _scanDirectory(dir, results);
    results.sort((a, b) => a.path.compareTo(b.path));
    return results;
  }

  /// [directory] içindeki yerel dosyaları recursive olarak tarar.
  void _scanDirectory(Directory directory, List<_ComicFileReference> results) {
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
            results.add(
              _ComicFileReference(
                path: p.normalize(entity.path),
                name: p.basename(entity.path),
              ),
            );
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
  String _makeId(String filePath) => SafFileAccessService.isSafUri(filePath)
      ? filePath
      : p.normalize(filePath);
}

class _ComicFileReference {
  const _ComicFileReference({required this.path, required this.name});

  final String path;
  final String name;
}
