import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../decoders/comic_decoder_factory.dart';
import '../decoders/i_comic_decoder.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Tarama Sonucu
// ═══════════════════════════════════════════════════════════════════════════════

/// Tek bir dosyanın kütüphane tarama sonucunu taşır.
/// Tüm formatlar için ortaktır: ZIP, RAR, PDF.
class ComicScanResult {
  final String filePath;
  final String title;
  final Uint8List? coverImageBytes;
  final int totalPages;
  final String? error;

  const ComicScanResult({
    required this.filePath,
    required this.title,
    this.coverImageBytes,
    required this.totalPages,
    this.error,
  });

  bool get hasError => error != null;
  bool get isValid => !hasError && totalPages > 0;
}

// ═══════════════════════════════════════════════════════════════════════════════
// ArchiveService
// ═══════════════════════════════════════════════════════════════════════════════

/// Tüm desteklenen formatlar için merkezi servis.
///
/// Dahili olarak [ComicDecoderFactory] kullanır:
/// - ZIP/CBZ → [ZipCbzDecoder]  (package:archive, Isolate)
/// - RAR/CBR → [RarCbrDecoder]  (koni_archive, Isolate)
/// - PDF     → [PdfDecoder]     (pdfx, native, ana thread)
class ArchiveService {
  const ArchiveService();

  // ─── Kütüphane Tarama ──────────────────────────────────────────────────────

  /// [filePath] dosyasını tarar: kapak görseli ve sayfa sayısını döner.
  /// Kütüphane listesi oluşturulurken kullanılır (tek seferlik).
  Future<ComicScanResult> scanFile(String filePath) async {
    final title = p.basenameWithoutExtension(filePath);
    IComicDecoder? decoder;

    try {
      decoder = ComicDecoderFactory.createForFile(filePath);
      final pageCount = await decoder.getPageCount();
      final coverBytes = await decoder.getCoverImage();

      return ComicScanResult(
        filePath: filePath,
        title: title,
        coverImageBytes: coverBytes,
        totalPages: pageCount,
      );
    } on UnsupportedError catch (e) {
      return ComicScanResult(
        filePath: filePath,
        title: title,
        totalPages: 0,
        error: e.message,
      );
    } catch (e) {
      return ComicScanResult(
        filePath: filePath,
        title: title,
        totalPages: 0,
        error: 'Dosya okunamadı: ${e.runtimeType}',
      );
    } finally {
      await decoder?.dispose();
    }
  }

  // ─── Okuyucu İçin ─────────────────────────────────────────────────────────

  /// Okuyucu için kalıcı decoder oluşturur.
  ///
  /// Kullanım:
  /// ```dart
  /// final decoder = archiveService.createDecoder(comic.filePath);
  /// // ... okuma boyunca kullan ...
  /// await decoder.dispose(); // okuyucu kapanınca
  /// ```
  IComicDecoder createDecoder(String filePath) {
    return ComicDecoderFactory.createForFile(filePath);
  }

  /// Belirli bir sayfayı yükler.
  /// ⚠️ Her çağrıda yeni decoder oluşturur → tek seferlik kullanım için.
  /// Okuyucuda sürekli çağrı için [createDecoder] kullanın.
  Future<Uint8List?> loadPageAt(String filePath, int pageIndex) async {
    final decoder = ComicDecoderFactory.createForFile(filePath);
    try {
      return await decoder.getPage(pageIndex);
    } finally {
      await decoder.dispose();
    }
  }
}
