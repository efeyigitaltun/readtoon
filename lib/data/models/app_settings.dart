/// Tüm uygulama ayarlarını tutan saf Dart modeli.
/// Hive Box&lt;dynamic&gt;'den key-value çiftleriyle okunur/yazılır.
/// [AppSettingsNotifier] tarafından yönetilir.
class AppSettings {
  /// Seçili manga/webtoon klasörü. null → henüz seçilmemiş.
  final String? folderPath;

  // ─── Okuyucu Ayarları ──────────────────────────────────────────────────────

  /// true → Webtoon (dikey ListView), false → Manga (yatay PageView).
  final bool isWebtoonMode;

  /// Manga modunda sağdan sola okuma yönü (RTL).
  final bool isRTL;

  /// Çift dokunuşla zoom etkinleştirme.
  final bool doubleTapZoom;

  // ─── Genel Ayarlar ─────────────────────────────────────────────────────────

  /// Okuma sırasında ekranı uyku moduna geçirme (Wakelock).
  final bool keepScreenOn;

  /// Uygulama başladığında kütüphaneyi otomatik tara.
  final bool scanOnStartup;

  const AppSettings({
    this.folderPath,
    this.isWebtoonMode = true,
    this.isRTL = true,
    this.doubleTapZoom = true,
    this.keepScreenOn = false,
    this.scanOnStartup = false,
  });

  /// Null yapılabilir [folderPath] için özel bir sentinal olmadan copyWith.
  /// [clearFolder] true verilirse folderPath null yapılır.
  AppSettings copyWith({
    String? folderPath,
    bool clearFolder = false,
    bool? isWebtoonMode,
    bool? isRTL,
    bool? doubleTapZoom,
    bool? keepScreenOn,
    bool? scanOnStartup,
  }) {
    return AppSettings(
      folderPath: clearFolder ? null : (folderPath ?? this.folderPath),
      isWebtoonMode: isWebtoonMode ?? this.isWebtoonMode,
      isRTL: isRTL ?? this.isRTL,
      doubleTapZoom: doubleTapZoom ?? this.doubleTapZoom,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
      scanOnStartup: scanOnStartup ?? this.scanOnStartup,
    );
  }
}
