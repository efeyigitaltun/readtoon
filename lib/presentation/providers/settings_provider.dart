import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/file_picker_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Servis Provider
// ═══════════════════════════════════════════════════════════════════════════════

final filePickerServiceProvider = Provider<FilePickerService>(
  (ref) => const FilePickerService(),
);

// ═══════════════════════════════════════════════════════════════════════════════
// Ayarlar State
// ═══════════════════════════════════════════════════════════════════════════════

/// Seçili manga klasör yolunu yönetir.
/// [null] → kullanıcı henüz klasör seçmemiş (setup ekranı gösterilir).
class SelectedFolderNotifier extends Notifier<String?> {
  @override
  String? build() {
    // Hive'dan kayıtlı yolu oku
    return ref.read(filePickerServiceProvider).getSavedFolderPath();
  }

  /// Sistem klasör seçicisini açar; seçim yapılırsa durumu günceller.
  Future<String?> pickFolder() async {
    final service = ref.read(filePickerServiceProvider);
    final path = await service.pickMangaDirectory();

    if (path != null) {
      await service.saveFolderPath(path);
      state = path;
    }

    return path;
  }

  /// Klasör seçimini sıfırlar (setup ekranına dön).
  Future<void> clearFolder() async {
    await ref.read(filePickerServiceProvider).clearSavedFolder();
    state = null;
  }
}

final selectedFolderProvider = NotifierProvider<SelectedFolderNotifier, String?>(
  SelectedFolderNotifier.new,
);

// ─── Okuma Modu Tercihi ────────────────────────────────────────────────────────

class ReadingModeNotifier extends Notifier<String> {
  @override
  String build() {
    return ref.read(filePickerServiceProvider).getSavedReadingMode();
  }

  Future<void> setMode(String mode) async {
    await ref.read(filePickerServiceProvider).saveReadingMode(mode);
    state = mode;
  }

  bool get isWebtoon => state == 'webtoon';
}

final readingModeProvider = NotifierProvider<ReadingModeNotifier, String>(
  ReadingModeNotifier.new,
);
