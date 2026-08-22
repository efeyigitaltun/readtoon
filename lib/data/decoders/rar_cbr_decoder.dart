import 'package:flutter/foundation.dart';
import 'package:koni_archive/io.dart';

import 'i_comic_decoder.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Top-level Isolate fonksiyonları – compute() için
// koni_archive saf Dart → Isolate içinde güvenle çalışır.
// ═══════════════════════════════════════════════════════════════════════════════

/// [filePath] içindeki sıralı görüntü dosyası isimlerini döner.
/// koni_archive format-agnostik: RAR4, RAR5, CBR hepsini açar.
Future<List<String>> _listRarPages(String filePath) async {
  final archive = await openArchiveFile(filePath);
  try {
    return archive.files
        .where((e) => isComicImageFile(e.path))
        .map((e) => e.path)
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  } finally {
    await archive.close();
  }
}

/// [params[0]] = filePath, [params[1]] = pageName
/// Yalnızca belirtilen sayfayı çözer → RAM sınırlıdır.
Future<Uint8List?> _readRarPage(List<dynamic> params) async {
  final filePath = params[0] as String;
  final pageName = params[1] as String;

  final archive = await openArchiveFile(filePath);
  try {
    final entry = archive.entry(pageName);
    if (entry == null) return null;
    // maxSize: 50MB – aşılırsa null dönülür; bozuk/aşırı büyük sayfaları korur
    return await archive.readBytes(entry, maxSize: 50 << 20);
  } catch (_) {
    return null;
  } finally {
    await archive.close();
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// RarCbrDecoder
// ═══════════════════════════════════════════════════════════════════════════════

/// .cbr ve .rar dosyaları için decoder.
/// [package:koni_archive] tabanlı – clean-room RAR4/RAR5, pure Dart.
/// Tüm CPU-yoğun işler [compute] ile ayrı Isolate'ta çalışır.
class RarCbrDecoder implements IComicDecoder {
  final String filePath;

  /// Sayfa adları Isolate'ta yüklenir ve önbelleğe alınır.
  List<String>? _cachedPageNames;

  RarCbrDecoder(this.filePath);

  Future<List<String>> _getPageNames() async {
    _cachedPageNames ??= await compute(_listRarPages, filePath);
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
    return compute(_readRarPage, [filePath, names[index]]);
  }

  @override
  Future<void> dispose() async {
    _cachedPageNames = null;
  }
}
