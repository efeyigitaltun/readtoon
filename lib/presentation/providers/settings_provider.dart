import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../core/constants/app_constants.dart';
import '../../data/models/app_settings.dart';
import '../../data/services/file_picker_service.dart';

final filePickerServiceProvider = Provider<FilePickerService>(
  (ref) => const FilePickerService(),
);

/// Uygulama ayarlarını Riverpod ve Hive arasında eş zamanlı tutar.
class AppSettingsNotifier extends Notifier<AppSettings> {
  Box<dynamic> get _box => Hive.box<dynamic>(AppConstants.settingsBox);

  @override
  AppSettings build() {
    final legacyPath = _box.get(AppConstants.settingsKeyFolderPath) as String?;
    final storedPaths = _box.get(AppConstants.settingsKeyFolderPaths);
    final folderPaths = storedPaths is List
        ? storedPaths
              .whereType<String>()
              .where((path) => path.isNotEmpty)
              .toSet()
              .toList()
        : <String>[];

    // Eski sürümlerde tek klasör saklanıyordu. Eski anahtarı lokasyon listesine
    // dahil ederek mevcut kullanıcıların kitaplıklarını koru.
    if (folderPaths.isEmpty && legacyPath != null && legacyPath.isNotEmpty) {
      folderPaths.add(legacyPath);
    }

    final storedSelection =
        _box.get(AppConstants.settingsKeyActiveFolderPath) as String?;
    final selectedFolderPath = folderPaths.contains(storedSelection)
        ? storedSelection
        : null;

    return AppSettings(
      folderPath: folderPaths.isEmpty ? legacyPath : folderPaths.first,
      folderPaths: List.unmodifiable(folderPaths),
      selectedFolderPath: selectedFolderPath,
      isWebtoonMode:
          _box.get(AppConstants.settingsKeyWebtoonMode, defaultValue: true)
              as bool,
      isRTL: _box.get(AppConstants.settingsKeyRTL, defaultValue: true) as bool,
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

  // ─── Lokasyonlar ───────────────────────────────────────────────────────────

  Future<void> addFolderPath(String path) async {
    final normalized = path.trim();
    if (normalized.isEmpty || state.folderPaths.contains(normalized)) return;

    final folderPaths = [...state.folderPaths, normalized];
    await _box.put(AppConstants.settingsKeyFolderPaths, folderPaths);
    // Eski sürümler için birincil lokasyonu tutmaya devam et.
    await _box.put(AppConstants.settingsKeyFolderPath, folderPaths.first);
    state = state.copyWith(
      folderPaths: List.unmodifiable(folderPaths),
      folderPath: folderPaths.first,
    );
  }

  Future<void> removeFolderPath(String path) async {
    final folderPaths = state.folderPaths
        .where((item) => item != path)
        .toList();
    final selectedWasRemoved = state.selectedFolderPath == path;

    await _box.put(AppConstants.settingsKeyFolderPaths, folderPaths);
    if (folderPaths.isEmpty) {
      await _box.delete(AppConstants.settingsKeyFolderPath);
    } else {
      await _box.put(AppConstants.settingsKeyFolderPath, folderPaths.first);
    }

    if (selectedWasRemoved) {
      await _box.delete(AppConstants.settingsKeyActiveFolderPath);
    }

    state = state.copyWith(
      folderPaths: List.unmodifiable(folderPaths),
      folderPath: folderPaths.isEmpty ? null : folderPaths.first,
      clearFolder: folderPaths.isEmpty,
      clearSelectedFolder: selectedWasRemoved,
    );
  }

  Future<void> setSelectedFolderPath(String? path) async {
    if (path != null && !state.folderPaths.contains(path)) return;

    if (path == null) {
      await _box.delete(AppConstants.settingsKeyActiveFolderPath);
      state = state.copyWith(clearSelectedFolder: true);
    } else {
      await _box.put(AppConstants.settingsKeyActiveFolderPath, path);
      state = state.copyWith(selectedFolderPath: path);
    }
  }

  /// Geriye dönük çağrılar için: klasörü lokasyonlara ekler ve seçer.
  Future<void> setFolderPath(String path) async {
    await addFolderPath(path);
    await setSelectedFolderPath(path);
  }

  /// Tüm lokasyonları kaldırıp ilk kurulum durumuna döner.
  Future<void> clearFolderPath() async {
    await _box.put(AppConstants.settingsKeyFolderPaths, <String>[]);
    await _box.delete(AppConstants.settingsKeyFolderPath);
    await _box.delete(AppConstants.settingsKeyActiveFolderPath);
    state = state.copyWith(
      folderPaths: const [],
      clearFolder: true,
      clearSelectedFolder: true,
    );
  }

  // ─── Okuyucu Ayarları ──────────────────────────────────────────────────────

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

  // ─── Genel Ayarlar ─────────────────────────────────────────────────────────

  Future<void> setKeepScreenOn(bool value) async {
    await _box.put(AppConstants.settingsKeyKeepScreenOn, value);
    state = state.copyWith(keepScreenOn: value);
  }

  Future<void> setScanOnStartup(bool value) async {
    await _box.put(AppConstants.settingsKeyScanOnStartup, value);
    state = state.copyWith(scanOnStartup: value);
  }
}

final appSettingsProvider = NotifierProvider<AppSettingsNotifier, AppSettings>(
  AppSettingsNotifier.new,
);
