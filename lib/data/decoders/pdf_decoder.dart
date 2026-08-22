import 'dart:typed_data';

import 'package:pdfx/pdfx.dart';

import 'i_comic_decoder.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// PdfDecoder
// ═══════════════════════════════════════════════════════════════════════════════

/// .pdf dosyaları için decoder.
///
/// [pdfx] paketi Android native PdfRenderer kullanır → platform channel.
/// Platform channel yalnızca ana (UI) Isolate'ta çalışır;
/// bu nedenle PDF işlemleri compute() ile DEĞİL, async olarak ana thread'de yürütülür.
///
/// RAM Optimizasyonu:
/// - Doküman açık tutulur (metadata + sayfa listesi için ucuz).
/// - Her [getPage] çağrısında yalnızca o sayfa render edilir → page.close() zorunlu.
/// - [dispose] çağrılana kadar doküman açık kalır.
class PdfDecoder implements IComicDecoder {
  final String filePath;

  /// Lazy açılan PDF dokümanı. [dispose] çağrısında kapatılır.
  PdfDocument? _document;

  /// Kapak küçük resmi için render genişliği (piksel).
  static const double _coverWidth = 360.0;

  /// Okuma için render ölçeği (sayfa boyutunun katı).
  static const double _readScale = 2.0;

  PdfDecoder(this.filePath);

  // ─── Dahili ─────────────────────────────────────────────────────────────────

  Future<PdfDocument> _getDocument() async {
    _document ??= await PdfDocument.openFile(filePath);
    return _document!;
  }

  Future<Uint8List?> _renderPage(PdfPage page, {bool isCover = false}) async {
    try {
      late final double renderWidth;
      late final double renderHeight;

      if (isCover) {
        // Küçük resim için sabit genişlik, oranı koru
        renderWidth = _coverWidth;
        renderHeight = page.height * (_coverWidth / page.width);
      } else {
        // Okuma için yüksek kalite
        renderWidth = page.width * _readScale;
        renderHeight = page.height * _readScale;
      }

      final image = await page.render(
        width: renderWidth,
        height: renderHeight,
        format: PdfPageImageFormat.jpeg,
        backgroundColor: '#FFFFFF',
      );

      return image?.bytes;
    } finally {
      // Android'de sayfa kapatılmadan yeni sayfa açılamaz → RAM critical
      await page.close();
    }
  }

  // ─── IComicDecoder ──────────────────────────────────────────────────────────

  @override
  Future<int> getPageCount() async {
    final doc = await _getDocument();
    return doc.pagesCount;
  }

  @override
  Future<Uint8List?> getCoverImage() async {
    final doc = await _getDocument();
    if (doc.pagesCount == 0) return null;
    // pdfx sayfa numarası 1'den başlar
    final page = await doc.getPage(1);
    return _renderPage(page, isCover: true);
  }

  @override
  Future<Uint8List?> getPage(int index) async {
    final doc = await _getDocument();
    if (index < 0 || index >= doc.pagesCount) return null;
    // 0-tabanlı index → 1-tabanlı pdfx sayfa numarasına dönüştür
    final page = await doc.getPage(index + 1);
    return _renderPage(page, isCover: false);
  }

  @override
  Future<void> dispose() async {
    await _document?.close();
    _document = null;
  }
}
