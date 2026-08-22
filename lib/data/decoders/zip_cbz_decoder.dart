import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';

import 'i_comic_decoder.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Top-level Isolate fonksiyonları – compute() için
// (compute yalnızca top-level/static fonksiyon kabul eder)
// ═══════════════════════════════════════════════════════════════════════════════

/// [filePath] içindeki sıralı görüntü dosyası isimlerini döner.
/// InputFileStream → sadece merkezi dizin okunur, içerik çözülmez.
List<String> _listZipPages(String filePath) {
  InputFileStream? stream;
  try {
    stream = InputFileStream(filePath);
    final archive = ZipDecoder().decodeBuffer(stream);
    return archive.files
        .where((f) => f.isFile && isComicImageFile(f.name))
        .map((f) => f.name)
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  } catch (_) {
    return [];
  } finally {
    stream?.close();
  }
}

/// [params[0]] = filePath, [params[1]] = pageName
/// Yalnızca belirtilen sayfanın sıkıştırmasını açar → RAM tasarrufu.
Uint8List? _readZipPage(List<dynamic> params) {
  final filePath = params[0] as String;
  final pageName = params[1] as String;
  InputFileStream? stream;

  try {
    stream = InputFileStream(filePath);
    final archive = ZipDecoder().decodeBuffer(stream);
    final entry = archive.files.where((f) => f.name == pageName).firstOrNull;
    if (entry == null || !entry.isFile) return null;
    return entry.content as Uint8List?;
  } catch (_) {
    return null;
  } finally {
    stream?.close();
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ZipCbzDecoder
// ═══════════════════════════════════════════════════════════════════════════════

/// .cbz ve .zip dosyaları için decoder.
/// [package:archive] tabanlı – stabil ve kanıtlanmış.
/// Tüm CPU-yoğun işler [compute] ile ayrı Isolate'ta çalışır.
class ZipCbzDecoder implements IComicDecoder {
  final String filePath;

  /// Sayfa adları Isolate'ta yüklenir ve önbelleğe alınır.
  List<String>? _cachedPageNames;

  ZipCbzDecoder(this.filePath);

  Future<List<String>> _getPageNames() async {
    _cachedPageNames ??= await compute(_listZipPages, filePath);
    return _cachedPageNames!;
  }

  @override
  Future<int> getPageCount() async => (await _getPageNames()).length;

  @override
  Future<Uint8List?> getCoverImage() => getPage(0);

  @override
  Future<Uint8List?> getPage(int index) async {
    final names = await _getPageNames();
    if (index < 0 || index >= names.length) return null;

    // Yalnızca bu sayfanın sıkıştırmasını Isolate'ta aç
    return compute(_readZipPage, [filePath, names[index]]);
  }

  @override
  Future<void> dispose() async {
    _cachedPageNames = null; // önbelleği temizle
  }
}
