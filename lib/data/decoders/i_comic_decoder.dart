import 'dart:typed_data';

/// Format-agnostik comic okuyucu arayüzü (Strategy/Interface).
///
/// [ZipCbzDecoder], [RarCbrDecoder] ve [PdfDecoder] bu arayüzü uygular.
/// [ComicDecoderFactory] dosya uzantısına göre doğru uygulamayı seçer.
///
/// RAM Optimizasyonu: Her [getPage] çağrısı yalnızca o sayfanın verisini
/// çözer/render eder. Sayfalar aynı anda belleğe yüklenmez (Lazy Loading).
abstract interface class IComicDecoder {
  /// Arşiv/doküman içindeki toplam sayfa sayısını döner.
  Future<int> getPageCount();

  /// Kapak görselini döner – genellikle ilk sayfa.
  /// Kütüphane ızgarasındaki önbellek görüntüsü için kullanılır.
  Future<Uint8List?> getCoverImage();

  /// [index] numaralı sayfanın ham piksel verisini döner (0 tabanlı).
  ///
  /// - Arşiv formatları: Yalnızca bu sayfa çözülür, diğerleri sıkıştırılı kalır.
  /// - PDF: Yalnızca bu sayfa render edilir, ardından kaynak serbest bırakılır.
  Future<Uint8List?> getPage(int index);

  /// Açık dosya tanıtıcılarını, bellek alanlarını ve diğer kaynakları serbest bırakır.
  /// Okuyucu kapatıldığında mutlaka çağrılmalıdır.
  Future<void> dispose();
}

// ─── Paylaşılan yardımcı ───────────────────────────────────────────────────────

/// Bir dosya adının desteklenen görüntü uzantısıyla bitip bitmediğini döner.
/// top-level olarak tanımlıdır → Isolate.run / compute içinden erişilebilir.
bool isComicImageFile(String name) {
  // Yalnızca dosya adını al (arşiv içindeki dizin yolunu sil)
  final filename = name.split('/').last.toLowerCase();
  return filename.endsWith('.jpg') ||
      filename.endsWith('.jpeg') ||
      filename.endsWith('.png') ||
      filename.endsWith('.webp') ||
      filename.endsWith('.gif') ||
      filename.endsWith('.avif');
}
