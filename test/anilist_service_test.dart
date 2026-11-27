import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:readtoon/data/models/anilist_media.dart';
import 'package:readtoon/data/services/anilist_service.dart';

void main() {
  test('searchManhwa sends Korean origin filter and parses media', () async {
    late Map<String, dynamic> requestBody;
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.toString(), 'https://graphql.anilist.co');
      requestBody = jsonDecode(request.body) as Map<String, dynamic>;

      return http.Response(
        jsonEncode({
          'data': {
            'Page': {
              'media': [
                {
                  'id': 42,
                  'title': {
                    'romaji': 'Romaji title',
                    'english': 'English title',
                  },
                  'coverImage': {'large': 'https://example.com/cover.jpg'},
                  'bannerImage': 'https://example.com/banner.jpg',
                  'description': 'A test summary',
                  'genres': ['Action'],
                  'status': 'RELEASING',
                  'chapters': 52,
                  'countryOfOrigin': 'KR',
                  'format': 'MANHWA',
                  'averageScore': 87,
                },
              ],
            },
          },
        }),
        200,
      );
    });
    final service = AniListService(client: client);

    final results = await service.searchManhwa('  Solo Leveling  ');
    final variables = requestBody['variables'] as Map<String, dynamic>;
    final query = requestBody['query'] as String;

    expect(query, contains('type: MANGA'));
    expect(query, contains('isAdult: false'));
    expect(query, contains('search: \$search'));
    expect(query, contains('countryOfOrigin: \$countryOfOrigin'));
    expect(variables['search'], 'Solo Leveling');
    expect(variables['countryOfOrigin'], 'KR');
    expect(results, hasLength(1));
    expect(results.single.title, 'English title');
    expect(results.single.totalChapters, 52);
    expect(results.single.countryOfOrigin, 'KR');

    service.close();
    client.close();
  });

  test('trending query uses AniList sort and omits absent filters', () async {
    late Map<String, dynamic> requestBody;
    final client = MockClient((request) async {
      requestBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'data': {
            'Page': {
              'media': [
                {
                  'id': 7,
                  'title': null,
                  'coverImage': null,
                  'bannerImage': null,
                  'genres': null,
                  'chapters': null,
                  'averageScore': null,
                },
              ],
            },
          },
        }),
        200,
      );
    });
    final service = AniListService(client: client);

    final results = await service.getTrending();
    final variables = requestBody['variables'] as Map<String, dynamic>;
    final query = requestBody['query'] as String;

    expect(variables['sort'], ['TRENDING_DESC']);
    expect(variables.containsKey('search'), isFalse);
    expect(variables.containsKey('countryOfOrigin'), isFalse);
    expect(query, contains('sort: \$sort'));
    expect(query, contains('isAdult: false'));
    expect(query, isNot(contains('search:')));
    expect(query, isNot(contains('countryOfOrigin:')));
    expect(results.single.title, 'Manga #7');
    expect(results.single.coverUrl, isEmpty);
    expect(results.single.genres, isEmpty);
    expect(results.single.totalChapters, isNull);
    expect(results.single.averageScore, isNull);

    service.close();
    client.close();
  });

  test('unexpected genres JSON type is treated as an empty list', () {
    final media = AniListMedia.fromJson({
      'id': 8,
      'genres': {'not': 'an array'},
    });

    expect(media.genres, isEmpty);
  });

  test('empty search does not make an API request', () async {
    final client = MockClient((_) async {
      fail('Empty search should not make an HTTP request.');
    });
    final service = AniListService(client: client);

    expect(await service.searchManga('  '), isEmpty);

    service.close();
    client.close();
  });
}
