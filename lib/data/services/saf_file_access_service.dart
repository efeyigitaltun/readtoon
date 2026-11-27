import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:saf/saf.dart';

/// Bridges persisted Storage Access Framework URIs to the local-file APIs used
/// by the existing comic decoders.
class SafFileAccessService {
  SafFileAccessService({Saf? saf}) : _saf = saf ?? Saf();

  final Saf _saf;

  static bool isSafUri(String value) =>
      Uri.tryParse(value)?.scheme == 'content';

  Future<SafDocumentFile?> pickDirectory() => _saf.pickDirectory();

  Stream<SafWalkEntry> walk(String directoryUri) => _saf.walk(directoryUri);

  Future<SafDocumentFile?> stat(String uri) => _saf.stat(uri);

  Future<List<SafDocumentFile>> list(String uri) => _saf.list(uri);

  /// SAF-backed archives are copied into the app cache because archive and PDF
  /// decoders intentionally continue to consume ordinary local paths.
  Future<String> ensureLocalFile(String uri, {String? displayName}) async {
    if (!isSafUri(uri)) return uri;

    final name = (displayName?.trim().isNotEmpty ?? false)
        ? displayName!.trim()
        : _nameFromUri(uri);
    final extension = p.extension(name).toLowerCase();
    if (extension.isEmpty) {
      throw FormatException('SAF dosyasının uzantısı belirlenemedi: $name');
    }

    final cacheDirectory = Directory(
      p.join((await getTemporaryDirectory()).path, 'readtoon_saf_cache'),
    );
    await cacheDirectory.create(recursive: true);
    final localPath = p.join(
      cacheDirectory.path,
      '${_stableHash(uri)}$extension',
    );
    final localFile = File(localPath);
    if (await localFile.exists()) await localFile.delete();

    await _saf.copyToLocalFile(uri, localPath);
    if (!await localFile.exists()) {
      throw FileSystemException(
        'SAF dosyası önbelleğe kopyalanamadı.',
        localPath,
      );
    }
    return localPath;
  }

  String _nameFromUri(String uri) {
    final parsed = Uri.parse(uri);
    if (parsed.pathSegments.isEmpty) return 'comic';
    return Uri.decodeComponent(parsed.pathSegments.last);
  }

  String _stableHash(String value) {
    var first = 0x811c9dc5;
    var second = 0x9e3779b9;
    for (final unit in value.codeUnits) {
      first = ((first ^ unit) * 0x01000193) & 0xffffffff;
      second = ((second ^ (unit + 0x9e3779b9)) * 0x85ebca6b) & 0xffffffff;
    }
    return '${first.toRadixString(16).padLeft(8, '0')}'
        '${second.toRadixString(16).padLeft(8, '0')}';
  }
}
