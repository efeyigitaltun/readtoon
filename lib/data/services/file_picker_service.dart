import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:hive/hive.dart';

import '../../core/constants/app_constants.dart';

/// Kullanıcıdan manga klasörü seçimini alır ve SAF iznini kalıcı olarak saklar.
///
/// Android'de [FilePicker.platform.getDirectoryPath] çağrısı
/// ACTION_OPEN_DOCUMENT_TREE intent'i kullanır (SAF). Dönen yol
/// [AppConstants.settingsKeyFolderPath] anahtarıyla Hive'a yazılır.
class FilePickerService {
  const FilePickerService();

  // ─── Klasör Seçimi ──────────────────────────────────────────────────────────

  /// Sistem dosya seçiciyi açar ve seçilen klasör yolunu döner.
  /// Kullanıcı iptal ederse [null] döner.
  Future<String?> pickMangaDirectory() async {
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Manga klasörünü seçin',
    );
    return path;
  }

  /// Seçilen klasör yolunu Hive'a kaydeder (kalıcı).
  Future<void> saveFolderPath(String path) async {
    final box = Hive.box<dynamic>(AppConstants.settingsBox);
    await box.put(AppConstants.settingsKeyFolderPath, path);
  }

  /// Kayıtlı klasör yolunu döner.
  /// [null] → henüz klasör seçilmemiş (onboarding gerekli).
  String? getSavedFolderPath() {
    final box = Hive.box<dynamic>(AppConstants.settingsBox);
    return box.get(AppConstants.settingsKeyFolderPath) as String?;
  }

  /// Kayıtlı klasörü sıfırlar (setup ekranına yönlendirme için).
  Future<void> clearSavedFolder() async {
    final box = Hive.box<dynamic>(AppConstants.settingsBox);
    await box.delete(AppConstants.settingsKeyFolderPath);
  }

  /// Seçilen klasörün hâlâ erişilebilir olup olmadığını kontrol eder.
  bool isFolderAccessible(String folderPath) {
    return Directory(folderPath).existsSync();
  }

}
