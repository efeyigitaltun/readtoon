/// Bir kütüphane lokasyonunun dosya sistemi ve okuma geçmişi istatistikleri.
class FolderLibraryStats {
  const FolderLibraryStats({
    required this.folderPath,
    required this.totalBooks,
    required this.totalBytes,
    required this.seriesCount,
    required this.readBooks,
    required this.unreadBooks,
    this.folderNameOverride,
  });

  final String folderPath;
  final String? folderNameOverride;
  final int totalBooks;
  final int totalBytes;
  final int seriesCount;
  final int readBooks;
  final int unreadBooks;

  String get folderName => folderNameOverride ?? nameFromPath(folderPath);

  static String nameFromPath(String path) {
    final uri = Uri.tryParse(path);
    if (uri?.scheme == 'content' && uri!.pathSegments.isNotEmpty) {
      return Uri.decodeComponent(uri.pathSegments.last);
    }
    final segments = path
        .split(RegExp(r'[/\\]+'))
        .where((segment) => segment.isNotEmpty)
        .toList();
    return segments.isEmpty ? path : segments.last;
  }

  String get totalSizeFormatted {
    const kilobyte = 1024;
    const megabyte = kilobyte * 1024;
    const gigabyte = megabyte * 1024;

    if (totalBytes >= gigabyte) {
      return '${_decimal(totalBytes / gigabyte, 2)} GB';
    }
    if (totalBytes >= megabyte) {
      return '${_decimal(totalBytes / megabyte, 2)} MB';
    }
    if (totalBytes >= kilobyte) {
      return '${_decimal(totalBytes / kilobyte, 1)} KB';
    }
    return '$totalBytes B';
  }

  static String _decimal(double value, int digits) =>
      value.toStringAsFixed(digits).replaceAll('.', ',');
}
