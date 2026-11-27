import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/anilist_media.dart';
import '../../data/services/anilist_service.dart';

final aniListServiceProvider = Provider<AniListService>((ref) {
  final service = AniListService();
  ref.onDispose(service.close);
  return service;
});

final trendingMangaProvider = FutureProvider.autoDispose<List<AniListMedia>>((
  ref,
) {
  return ref.watch(aniListServiceProvider).getTrending(perPage: 12);
});

final popularManhwaProvider = FutureProvider.autoDispose<List<AniListMedia>>((
  ref,
) {
  return ref.watch(aniListServiceProvider).getPopularManhwa(perPage: 12);
});

final topRatedMangaProvider = FutureProvider.autoDispose<List<AniListMedia>>((
  ref,
) {
  return ref.watch(aniListServiceProvider).getTopRated(perPage: 12);
});

final mangaSearchProvider = FutureProvider.autoDispose
    .family<List<AniListMedia>, String>((ref, query) {
      final normalizedQuery = query.trim();
      if (normalizedQuery.isEmpty) return const [];
      return ref
          .watch(aniListServiceProvider)
          .searchManga(normalizedQuery, perPage: 30);
    });
