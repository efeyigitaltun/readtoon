import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:hive/hive.dart';

import 'saf_file_access_service.dart';

import '../../core/constants/app_constants.dart';

/// Kullanıcıdan manga klasörü seçimini alır ve SAF iznini kalıcı olarak saklar.
///
/// Android'de kalıcı izinli SAF URI'si, diğer platformlarda dosya yolu döner.
class FilePickerService {
  const FilePickerService();

  // ─── Klasör Seçimi ──────────────────────────────────────────────────────────

  /// Sistem dosya seçiciyi açar ve seçilen klasör yolunu döner.
  /// Kullanıcı iptal ederse [null] döner.
  Future<String?> pickMangaDirectory() async {
    if (Platform.isAndroid) {
      final directory = await SafFileAccessService().pickDirectory();
      return directory?.uri;
    }

    return FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Manga klasörünü seçin',
    );
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
  Future<bool> isFolderAccessible(String folderPath) async {
    if (SafFileAccessService.isSafUri(folderPath)) {
      try {
        return await SafFileAccessService().stat(folderPath) != null;
      } catch (_) {
        return false;
      }
    }
    return Directory(folderPath).existsSync();
  }
}
