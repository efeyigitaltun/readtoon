import 'package:hive/hive.dart';

import '../../core/constants/app_constants.dart';

/// Kullanıcının AniList serisi için cihazda tuttuğu takip ve puan bilgileri.
class TrackedSeries extends HiveObject {
  final int mediaId;
  String title;
  String coverUrl;
  String? bannerUrl;
  TrackedSeriesStatus status;
  double _rating;
  int chaptersRead;
  int? totalChapters;
  String? reviewNote;
  DateTime updatedAt;
  List<String> completedLocalComicIds;
  bool isFavorite;

  TrackedSeries({
    required this.mediaId,
    required this.title,
    required this.coverUrl,
    this.bannerUrl,
    this.status = TrackedSeriesStatus.planToRead,
    double rating = 0.0,
    this.chaptersRead = 0,
    this.totalChapters,
    this.reviewNote,
    DateTime? updatedAt,
    List<String>? completedLocalComicIds,
    this.isFavorite = false,
  }) : _rating = normalizeRating(rating),
       updatedAt = updatedAt ?? DateTime.now(),
       completedLocalComicIds = List<String>.from(
         completedLocalComicIds ?? const [],
       ) {
    if (chaptersRead < 0) chaptersRead = 0;
    if (totalChapters != null && totalChapters! < 0) totalChapters = null;
  }

  /// 0–5 aralığında yarım yıldız adımlarına normalize edilmiş kullanıcı puanı.
  double get rating => _rating;

  set rating(double value) => _rating = normalizeRating(value);

  int? get chaptersRemaining {
    final total = totalChapters;
    if (total == null) return null;
    return (total - chaptersRead).clamp(0, total);
  }

  bool get isCompleted => status == TrackedSeriesStatus.completed;

  static double normalizeRating(num value) {
    final bounded = value.toDouble().clamp(0.0, 5.0);
    return (bounded * 2).round() / 2;
  }
}

enum TrackedSeriesStatus {
  reading,
  completed,
  planToRead,
  dropped;

  String get displayName => switch (this) {
    TrackedSeriesStatus.reading => 'Okuyorum',
    TrackedSeriesStatus.completed => 'Okudum',
    TrackedSeriesStatus.planToRead => 'Okuyacağım',
    TrackedSeriesStatus.dropped => 'Bıraktım',
  };

  static TrackedSeriesStatus fromStorage(Object? value) {
    return TrackedSeriesStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => TrackedSeriesStatus.planToRead,
    );
  }
}

/// Hive adapter; alan numaraları sabit tutularak eski kayıtlarla uyumludur.
class TrackedSeriesAdapter extends TypeAdapter<TrackedSeries> {
  @override
  final int typeId = AppConstants.trackedSeriesTypeId;

  @override
  TrackedSeries read(BinaryReader reader) {
    final fieldCount = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < fieldCount; i++) reader.readByte(): reader.read(),
    };

    final rawRating = fields[5];
    return TrackedSeries(
      mediaId: _asInt(fields[0]) ?? 0,
      title: fields[1] as String? ?? '',
      coverUrl: fields[2] as String? ?? '',
      bannerUrl: fields[3] as String?,
      status: TrackedSeriesStatus.fromStorage(fields[4]),
      rating: rawRating is num ? rawRating.toDouble() : 0.0,
      chaptersRead: _asInt(fields[6]) ?? 0,
      totalChapters: _asInt(fields[7]),
      reviewNote: fields[8] as String?,
      updatedAt: fields[9] as DateTime? ?? DateTime.now(),
      completedLocalComicIds:
          (fields[10] as List<dynamic>?)?.whereType<String>().toList() ??
          const [],
      isFavorite: fields[11] as bool? ?? false,
    );
  }

  @override
  void write(BinaryWriter writer, TrackedSeries obj) {
    writer
      ..writeByte(12)
      ..writeByte(0)
      ..write(obj.mediaId)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.coverUrl)
      ..writeByte(3)
      ..write(obj.bannerUrl)
      ..writeByte(4)
      ..write(obj.status.name)
      ..writeByte(5)
      ..write(obj.rating)
      ..writeByte(6)
      ..write(obj.chaptersRead)
      ..writeByte(7)
      ..write(obj.totalChapters)
      ..writeByte(8)
      ..write(obj.reviewNote)
      ..writeByte(9)
      ..write(obj.updatedAt)
      ..writeByte(10)
      ..write(obj.completedLocalComicIds)
      ..writeByte(11)
      ..write(obj.isFavorite);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrackedSeriesAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;

  static int? _asInt(dynamic value) => value is num ? value.toInt() : null;
}
