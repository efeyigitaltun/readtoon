/// Uygulama genelinde kullanılan sabitler
class AppConstants {
  AppConstants._();

  // ─── Hive Box İsimleri ─────────────────────────────────────────────────────
  static const String comicsBox = 'comics';
  static const String historyBox = 'history';
  static const String settingsBox = 'settings';

  // ─── Hive Settings Anahtarları ─────────────────────────────────────────────
  static const String settingsKeyFolderPath = 'selected_folder_path';
  static const String settingsKeyFolderUri = 'selected_folder_uri';
  static const String settingsKeyReadingMode = 'default_reading_mode';

  // ─── Okuma Modu Değerleri ──────────────────────────────────────────────────
  static const String readingModeWebtoon = 'webtoon';
  static const String readingModeManga = 'manga';

  // ─── Hive TypeAdapter ID'leri ──────────────────────────────────────────────
  static const int comicBookTypeId = 0;
  static const int readHistoryTypeId = 1;

  // ─── UI Sabitleri ──────────────────────────────────────────────────────────
  /// Kapak görseli köşe yarıçapı (piksel)
  static const double coverBorderRadius = 12.0;

  /// Izgara/liste genel padding
  static const double gridPadding = 16.0;

  /// Kütüphane ızgara sütun sayısı
  static const int gridCrossAxisCount = 3;

  /// Reader tap zone oranları (ekranın yüzdesi)
  static const double tapZonePrevRatio = 0.30; // sol %30
  static const double tapZoneNextRatio = 0.30; // sağ %30

  /// Menü overlay opaklığı (0-1)
  static const double menuOverlayOpacity = 0.90;
}
