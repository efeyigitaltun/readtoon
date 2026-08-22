import 'package:hive/hive.dart';

/// Bir mangada okuma ilerlemesini saklar.
/// Hive box: AppConstants.historyBox, key: [comicId]
class ReadHistory extends HiveObject {
  /// İlgili ComicBook'un [id] değeri
  String comicId;

  /// Kullanıcının en son bıraktığı sayfa indeksi (0 tabanlı)
  int currentPage;

  /// Okuma modu ('webtoon' | 'manga') – kaydederken saklanır
  String readingMode;

  /// Son okunma tarihi
  DateTime lastReadAt;

  ReadHistory({
    required this.comicId,
    required this.currentPage,
    required this.readingMode,
    required this.lastReadAt,
  });

  /// İlerleme yüzdesi (0.0 – 1.0) – UI progress bar için
  double progressOf(int totalPages) {
    if (totalPages <= 0) return 0.0;
    return (currentPage / totalPages).clamp(0.0, 1.0);
  }
}

/// Hive TypeAdapter – manuel yazıldı, build_runner gerektirmez.
class ReadHistoryAdapter extends TypeAdapter<ReadHistory> {
  @override
  final int typeId = 1;

  @override
  ReadHistory read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ReadHistory(
      comicId: (fields[0] as String?) ?? '',
      currentPage: (fields[1] as int?) ?? 0,
      readingMode: (fields[2] as String?) ?? 'webtoon',
      lastReadAt: (fields[3] as DateTime?) ?? DateTime.now(),
    );
  }

  @override
  void write(BinaryWriter writer, ReadHistory obj) {
    writer
      ..writeByte(4) // alan sayısı
      ..writeByte(0)
      ..write(obj.comicId)
      ..writeByte(1)
      ..write(obj.currentPage)
      ..writeByte(2)
      ..write(obj.readingMode)
      ..writeByte(3)
      ..write(obj.lastReadAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReadHistoryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
