import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/anilist_media.dart';

/// AniList GraphQL API'sine manga odaklı erişim sağlar.
class AniListService {
  AniListService({http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;

  static final Uri _endpoint = Uri.parse('https://graphql.anilist.co');

  static String _buildMediaQuery({
    required bool includeSearch,
    required bool includeCountry,
  }) {
    final variableDefinitions = <String>[
      r'$page: Int!',
      r'$perPage: Int!',
      r'$sort: [MediaSort]',
    ];
    final mediaArguments = <String>[
      'type: MANGA',
      'isAdult: false',
      r'sort: $sort',
    ];

    if (includeSearch) {
      variableDefinitions.add(r'$search: String!');
      mediaArguments.insert(1, r'search: $search');
    }
    if (includeCountry) {
      variableDefinitions.add(r'$countryOfOrigin: CountryCode!');
      mediaArguments.insert(
        mediaArguments.length - 1,
        r'countryOfOrigin: $countryOfOrigin',
      );
    }

    return '''
      query ReadToonMedia(${variableDefinitions.join(', ')}) {
        Page(page: \$page, perPage: \$perPage) {
          media(${mediaArguments.join(', ')}) {
            id
            title { romaji english native }
            coverImage { large extraLarge }
            bannerImage
            description(asHtml: false)
            genres
            status
            chapters
            countryOfOrigin
            format
            averageScore
          }
        }
      }
    ''';
  }

  final http.Client _client;
  final bool _ownsClient;

  /// Tüm manga türlerinde başlığa göre arama yapar.
  Future<List<AniListMedia>> searchManga(
    String query, {
    int page = 1,
    int perPage = 20,
  }) {
    return _search(
      query,
      page: page,
      perPage: perPage,
      sort: const ['SEARCH_MATCH'],
    );
  }

  /// Güney Kore menşeli manga/manhwa serilerinde arama yapar.
  Future<List<AniListMedia>> searchManhwa(
    String query, {
    int page = 1,
    int perPage = 20,
  }) {
    return _search(
      query,
      page: page,
      perPage: perPage,
      countryOfOrigin: 'KR',
      sort: const ['SEARCH_MATCH'],
    );
  }

  /// Çin menşeli manga/manhua serilerinde arama yapar.
  Future<List<AniListMedia>> searchManhua(
    String query, {
    int page = 1,
    int perPage = 20,
  }) {
    return _search(
      query,
      page: page,
      perPage: perPage,
      countryOfOrigin: 'CN',
      sort: const ['SEARCH_MATCH'],
    );
  }

  Future<List<AniListMedia>> getTrending({int page = 1, int perPage = 20}) {
    return _fetchMedia(
      page: page,
      perPage: perPage,
      sort: const ['TRENDING_DESC'],
    );
  }

  Future<List<AniListMedia>> getPopularManhwa({
    int page = 1,
    int perPage = 20,
  }) {
    return _fetchMedia(
      page: page,
      perPage: perPage,
      countryOfOrigin: 'KR',
      sort: const ['POPULARITY_DESC'],
    );
  }

  Future<List<AniListMedia>> getTopRated({int page = 1, int perPage = 20}) {
    return _fetchMedia(
      page: page,
      perPage: perPage,
      sort: const ['SCORE_DESC'],
    );
  }

  Future<List<AniListMedia>> _search(
    String query, {
    required int page,
    required int perPage,
    String? countryOfOrigin,
    required List<String> sort,
  }) {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) return Future.value(const []);

    return _fetchMedia(
      page: page,
      perPage: perPage,
      search: normalizedQuery,
      countryOfOrigin: countryOfOrigin,
      sort: sort,
    );
  }

  Future<List<AniListMedia>> _fetchMedia({
    required int page,
    required int perPage,
    String? search,
    String? countryOfOrigin,
    required List<String> sort,
  }) async {
    if (page < 1) {
      throw ArgumentError.value(page, 'page', '1 veya daha büyük olmalı.');
    }
    if (perPage < 1 || perPage > 50) {
      throw ArgumentError.value(perPage, 'perPage', '1–50 arasında olmalı.');
    }

    final normalizedSearch = search?.trim();
    final includeSearch = normalizedSearch?.isNotEmpty ?? false;
    final includeCountry = countryOfOrigin?.isNotEmpty ?? false;
    final variables = <String, Object>{
      'page': page,
      'perPage': perPage,
      'sort': sort,
    };
    if (includeSearch) variables['search'] = normalizedSearch!;
    if (includeCountry) variables['countryOfOrigin'] = countryOfOrigin!;

    late final http.Response response;
    try {
      response = await _client.post(
        _endpoint,
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'query': _buildMediaQuery(
            includeSearch: includeSearch,
            includeCountry: includeCountry,
          ),
          'variables': variables,
        }),
      );
    } on http.ClientException catch (error) {
      debugPrint('[AniList] Bağlantı hatası: ${error.message}');
      throw AniListApiException(
        'AniList bağlantısı kurulamadı: ${error.message}',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      _logResponseError('JSON yanıtı çözümlenemedi.', response);
      throw AniListApiException(
        'AniList geçerli JSON yanıtı döndürmedi.',
        statusCode: response.statusCode,
      );
    }

    if (decoded is! Map) {
      _logResponseError('Yanıt biçimi beklenenden farklı.', response);
      throw AniListApiException(
        'AniList yanıtının biçimi beklenenden farklı.',
        statusCode: response.statusCode,
      );
    }
    final payload = Map<String, dynamic>.from(decoded);

    final errors = payload['errors'];
    if (errors is List && errors.isNotEmpty) {
      final messages = errors
          .whereType<Map>()
          .map((error) => error['message'])
          .whereType<String>()
          .where((message) => message.isNotEmpty)
          .join('; ');
      _logResponseError(
        messages.isEmpty ? 'GraphQL isteği başarısız oldu.' : messages,
        response,
      );
      throw AniListApiException(
        messages.isEmpty ? 'AniList GraphQL isteği başarısız oldu.' : messages,
        statusCode: response.statusCode,
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      _logResponseError('HTTP isteği başarısız oldu.', response);
      throw AniListApiException(
        'AniList HTTP isteği başarısız oldu (${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }

    final data = payload['data'];
    final pageData = data is Map ? data['Page'] : null;
    final media = pageData is Map ? pageData['media'] : null;
    if (media is! List) {
      _logResponseError('Yanıtta manga listesi bulunamadı.', response);
      throw AniListApiException('AniList yanıtında manga listesi bulunamadı.');
    }

    return media
        .whereType<Map>()
        .map((item) => AniListMedia.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  void _logResponseError(String message, http.Response response) {
    debugPrint('[AniList] $message (HTTP ${response.statusCode})');
    if (response.body.isNotEmpty) {
      final body = response.body;
      debugPrint(body.length > 2000 ? body.substring(0, 2000) : body);
    }
  }

  /// Yalnızca servis kendi oluşturduğu istemciyi kapatır.
  void close() {
    if (_ownsClient) _client.close();
  }
}

class AniListApiException implements Exception {
  const AniListApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => statusCode == null
      ? 'AniListApiException: $message'
      : 'AniListApiException ($statusCode): $message';
}
