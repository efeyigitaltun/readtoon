import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../core/constants/app_constants.dart';
import '../../data/models/app_settings.dart';
import '../../data/services/file_picker_service.dart';
import '../../data/services/permission_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Servis Provider'ları (değişmedi)
// ═══════════════════════════════════════════════════════════════════════════════

final filePickerServiceProvider = Provider<FilePickerService>(
  (ref) => const FilePickerService(),
);

final permissionServiceProvider = Provider<PermissionService>(
  (ref) => const PermissionService(),
);

// ═══════════════════════════════════════════════════════════════════════════════
// Unified AppSettings Notifier
// ═══════════════════════════════════════════════════════════════════════════════

/// Tüm uygulama ayarlarını tek bir Notifier'da yönetir.
/// Her güncelleme hem Riverpod state'ini hem de Hive'ı senkronize eder.
class AppSettingsNotifier extends Notifier<AppSettings> {
  Box<dynamic> get _box => Hive.box<dynamic>(AppConstants.settingsBox);

  @override
  AppSettings build() {
    return AppSettings(
      folderPath: _box.get(AppConstants.settingsKeyFolderPath) as String?,
      isWebtoonMode:
          _box.get(AppConstants.settingsKeyWebtoonMode, defaultValue: true)
              as bool,
      isRTL:
          _box.get(AppConstants.settingsKeyRTL, defaultValue: true) as bool,
      doubleTapZoom:
          _box.get(AppConstants.settingsKeyDoubleTapZoom, defaultValue: true)
              as bool,
      keepScreenOn:
          _box.get(AppConstants.settingsKeyKeepScreenOn, defaultValue: false)
              as bool,
      scanOnStartup:
          _box.get(AppConstants.settingsKeyScanOnStartup, defaultValue: false)
              as bool,
    );
  }

  // ─── Klasör ───────────────────────────────────────────────────────────────

  Future<void> setFolderPath(String path) async {
    await _box.put(AppConstants.settingsKeyFolderPath, path);
    state = state.copyWith(folderPath: path);
  }

  Future<void> clearFolderPath() async {
    await _box.delete(AppConstants.settingsKeyFolderPath);
    state = state.copyWith(clearFolder: true);
  }

  // ─── Okuyucu Ayarları ────────────────────────────────────────────────────

  Future<void> setWebtoonMode(bool value) async {
    await _box.put(AppConstants.settingsKeyWebtoonMode, value);
    state = state.copyWith(isWebtoonMode: value);
  }

  Future<void> setRTL(bool value) async {
    await _box.put(AppConstants.settingsKeyRTL, value);
    state = state.copyWith(isRTL: value);
  }

  Future<void> setDoubleTapZoom(bool value) async {
    await _box.put(AppConstants.settingsKeyDoubleTapZoom, value);
    state = state.copyWith(doubleTapZoom: value);
  }

  // ─── Genel Ayarlar ───────────────────────────────────────────────────────

  Future<void> setKeepScreenOn(bool value) async {
    await _box.put(AppConstants.settingsKeyKeepScreenOn, value);
    state = state.copyWith(keepScreenOn: value);
  }

  Future<void> setScanOnStartup(bool value) async {
    await _box.put(AppConstants.settingsKeyScanOnStartup, value);
    state = state.copyWith(scanOnStartup: value);
  }
}

final appSettingsProvider =
    NotifierProvider<AppSettingsNotifier, AppSettings>(
  AppSettingsNotifier.new,
);
