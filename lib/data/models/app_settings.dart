/// Tüm uygulama ayarlarını tutan saf Dart modeli.
/// Hive dinamik ayar kutusundan key-value çiftleriyle okunur/yazılır.
/// [AppSettingsNotifier] tarafından yönetilir.
class AppSettings {
  /// Eski tek-klasör ayarıyla uyumluluk için ilk kayıtlı klasör.
  /// Aktif filtreyi belirtmez; bunun için [selectedFolderPath] kullanılır.
  final String? folderPath;

  /// Kütüphaneye eklenmiş bütün klasörler.
  final List<String> folderPaths;

  /// null ise tüm lokasyonlar, doluysa yalnızca bu lokasyon gösterilir.
  final String? selectedFolderPath;

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
    this.folderPaths = const [],
    this.selectedFolderPath,
    this.isWebtoonMode = true,
    this.isRTL = true,
    this.doubleTapZoom = true,
    this.keepScreenOn = false,
    this.scanOnStartup = false,
  });

  bool get hasFolders => folderPaths.isNotEmpty || folderPath != null;

  AppSettings copyWith({
    String? folderPath,
    bool clearFolder = false,
    List<String>? folderPaths,
    String? selectedFolderPath,
    bool clearSelectedFolder = false,
    bool? isWebtoonMode,
    bool? isRTL,
    bool? doubleTapZoom,
    bool? keepScreenOn,
    bool? scanOnStartup,
  }) {
    final updatedFolderPaths = folderPaths ?? this.folderPaths;
    final updatedFolderPath = clearFolder
        ? null
        : folderPath ??
              (folderPaths != null
                  ? (updatedFolderPaths.isEmpty
                        ? null
                        : updatedFolderPaths.first)
                  : this.folderPath);

    return AppSettings(
      folderPath: updatedFolderPath,
      folderPaths: updatedFolderPaths,
      selectedFolderPath: clearSelectedFolder
          ? null
          : selectedFolderPath ?? this.selectedFolderPath,
      isWebtoonMode: isWebtoonMode ?? this.isWebtoonMode,
      isRTL: isRTL ?? this.isRTL,
      doubleTapZoom: doubleTapZoom ?? this.doubleTapZoom,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
      scanOnStartup: scanOnStartup ?? this.scanOnStartup,
    );
  }
}
