/// Manga verisini AniList GraphQL API yanıtından taşır.
class AniListMedia {
  final int id;
  final String title;
  final String? englishTitle;
  final String? nativeTitle;
  final String coverUrl;
  final String? bannerUrl;
  final String? description;
  final List<String> genres;
  final String? status;
  final int? totalChapters;
  final String? countryOfOrigin;
  final String? format;
  final int? averageScore;

  const AniListMedia({
    required this.id,
    required this.title,
    this.englishTitle,
    this.nativeTitle,
    required this.coverUrl,
    this.bannerUrl,
    this.description,
    this.genres = const [],
    this.status,
    this.totalChapters,
    this.countryOfOrigin,
    this.format,
    this.averageScore,
  });

  factory AniListMedia.fromJson(Map<String, dynamic> json) {
    final titleData = _asStringMap(json['title']);
    final coverData = _asStringMap(json['coverImage']);
    final id = _asInt(json['id']) ?? 0;
    final romajiTitle = _asString(titleData['romaji']);
    final englishTitle = _asString(titleData['english']);
    final nativeTitle = _asString(titleData['native']);

    return AniListMedia(
      id: id,
      title: englishTitle ?? romajiTitle ?? nativeTitle ?? 'Manga #$id',
      englishTitle: englishTitle,
      nativeTitle: nativeTitle,
      coverUrl:
          _asString(coverData['extraLarge']) ??
          _asString(coverData['large']) ??
          '',
      bannerUrl: _asString(json['bannerImage']),
      description: _asString(json['description']),
      genres: _asStringList(json['genres']),
      status: _asString(json['status']),
      totalChapters: _asInt(json['chapters']),
      countryOfOrigin: _asString(json['countryOfOrigin']),
      format: _asString(json['format']),
      averageScore: _asInt(json['averageScore']),
    );
  }

  static Map<String, dynamic> _asStringMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return const {};
  }

  static String? _asString(dynamic value) =>
      value is String && value.isNotEmpty ? value : null;

  static List<String> _asStringList(dynamic value) {
    if (value is! List) return const [];
    return value.whereType<String>().toList(growable: false);
  }

  static int? _asInt(dynamic value) => value is num ? value.toInt() : null;
}
