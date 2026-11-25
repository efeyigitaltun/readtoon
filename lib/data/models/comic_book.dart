import 'dart:typed_data';

import 'package:hive/hive.dart';

import 'read_history.dart';

/// Kütüphanedeki her bir manga/webtoon dosyasını temsil eder.
/// Hive box: AppConstants.comicsBox, key: [id]
class ComicBook extends HiveObject {
  /// Benzersiz tanımlayıcı – dosya yolunun hash'i
  String id;

  /// Görüntülenecek başlık (dosya adı, uzantısız)
  String title;

  /// .cbz dosyasının tam yolu
  String filePath;

  /// Önbelleğe alınmış kapak görseli (ilk sayfa)
  Uint8List? coverImageBytes;

  /// Arşivdeki toplam sayfa sayısı
  int totalPages;

  /// Dosyanın bulunduğu ana klasör yolu
  String parentFolderPath;

  /// Kütüphaneye eklenme tarihi
  DateTime addedAt;

  /// Kullanıcının favori olarak işaretleyip işaretlemediği
  bool isFavorite;

  ComicBook({
    required this.id,
    required this.title,
    required this.filePath,
    this.coverImageBytes,
    required this.totalPages,
    required this.parentFolderPath,
    required this.addedAt,
    this.isFavorite = false,
  });

  /// Okuma durumunu okuma geçmişi ve toplam sayfa sayısına göre hesaplar.
  ComicReadingStatus readingStatus(ReadHistory? history) {
    if (history == null || history.currentPage == 0) {
      return ComicReadingStatus.unread;
    }
    if (totalPages > 0 && history.currentPage >= totalPages - 1) {
      return ComicReadingStatus.read;
    }
    return ComicReadingStatus.reading;
  }
}

enum ComicReadingStatus { unread, reading, read }

/// Hive TypeAdapter – manuel yazıldı, build_runner gerektirmez.
class ComicBookAdapter extends TypeAdapter<ComicBook> {
  @override
  final int typeId = 0;

  @override
  ComicBook read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ComicBook(
      id: (fields[0] as String?) ?? '',
      title: (fields[1] as String?) ?? '',
      filePath: (fields[2] as String?) ?? '',
      coverImageBytes: fields[3] as Uint8List?,
      totalPages: (fields[4] as int?) ?? 0,
      parentFolderPath: (fields[5] as String?) ?? '',
      addedAt: (fields[6] as DateTime?) ?? DateTime.now(),
      // Eski Hive kayıtlarında field 7 bulunmaz; varsayılanı favori değildir.
      isFavorite: (fields[7] as bool?) ?? false,
    );
  }

  @override
  void write(BinaryWriter writer, ComicBook obj) {
    writer
      ..writeByte(8) // alan sayısı
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.filePath)
      ..writeByte(3)
      ..write(obj.coverImageBytes)
      ..writeByte(4)
      ..write(obj.totalPages)
      ..writeByte(5)
      ..write(obj.parentFolderPath)
      ..writeByte(6)
      ..write(obj.addedAt)
      ..writeByte(7)
      ..write(obj.isFavorite);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ComicBookAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
