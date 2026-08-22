import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

/// Android depolama izni yönetimi.
///
/// Hiyerarşi:
///   Android 11+ (API 30+) → MANAGE_EXTERNAL_STORAGE (Tüm Dosyalara Erişim)
///   Android 10 ve altı    → READ_EXTERNAL_STORAGE (normal depolama izni)
///
/// Not: MANAGE_EXTERNAL_STORAGE istenmesi Android 11+'ta sistem Ayarlar
/// ekranını açar; kullanıcı dönünce [request()] sonucu güncellenir.
class PermissionService {
  const PermissionService();

  // ─── İzin İsteme ─────────────────────────────────────────────────────────

  /// Gerekli depolama iznini ister; verilmişse [true] döner.
  ///
  /// Akış:
  /// 1. MANAGE_EXTERNAL_STORAGE kontrol → zaten verilmişse hemen true
  /// 2. MANAGE_EXTERNAL_STORAGE iste → Android 11+'ta Ayarlar ekranı açılır
  /// 3. Hâlâ verilmemişse: READ_EXTERNAL_STORAGE (Android <11 fallback)
  Future<bool> requestStoragePermission() async {
    if (!Platform.isAndroid) return true;

    // ── Adım 1: MANAGE_EXTERNAL_STORAGE (Android 11+) ─────────────────────
    final manageStatus = await Permission.manageExternalStorage.status;

    if (manageStatus.isGranted) return true;

    // Kalıcı red → kullanıcıyı ayarlara yönlendirmek gerekir
    if (manageStatus.isPermanentlyDenied) return false;

    // İzin iste (Android 11+'ta "Tüm Dosyalara Erişim" ayarı açılır ve beklenir)
    final manageResult = await Permission.manageExternalStorage.request();
    if (manageResult.isGranted) return true;

    // ── Adım 2: READ_EXTERNAL_STORAGE (Android <11 veya MANAGE başarısız) ─
    final storageStatus = await Permission.storage.status;
    if (storageStatus.isGranted) return true;
    if (storageStatus.isPermanentlyDenied) return false;

    final storageResult = await Permission.storage.request();
    return storageResult.isGranted;
  }

  // ─── İzin Durumu Kontrol ─────────────────────────────────────────────────

  /// Dialog açmadan mevcut izin durumunu döner.
  Future<bool> isStoragePermissionGranted() async {
    if (!Platform.isAndroid) return true;

    if (await Permission.manageExternalStorage.isGranted) return true;
    if (await Permission.storage.isGranted) return true;

    return false;
  }

  /// [MANAGE_EXTERNAL_STORAGE] kalıcı olarak reddedilmişse [true] döner.
  /// Bu durumda sadece Ayarlar'dan el ile verilebilir.
  Future<bool> isPermanentlyDenied() async {
    if (!Platform.isAndroid) return false;

    if (await Permission.manageExternalStorage.isPermanentlyDenied) return true;
    if (await Permission.storage.isPermanentlyDenied) return true;

    return false;
  }

  // ─── Ayarlar ─────────────────────────────────────────────────────────────

  /// Uygulamanın sistem uygulama ayarları sayfasını açar.
  /// Kalıcı red durumunda kullanıcıya gösterilir.
  Future<void> openAppPermissionSettings() => openAppSettings();
}
