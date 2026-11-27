import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:readtoon/app.dart';
import 'package:readtoon/core/constants/app_constants.dart';
import 'package:readtoon/data/models/anilist_media.dart';
import 'package:readtoon/data/models/community_review.dart';
import 'package:readtoon/data/models/comic_book.dart';
import 'package:readtoon/data/models/read_history.dart';
import 'package:readtoon/data/models/tracked_series.dart';
import 'package:readtoon/data/services/anilist_service.dart';
import 'package:readtoon/data/services/firestore_review_service.dart';
import 'package:readtoon/presentation/providers/auth_provider.dart';
import 'package:readtoon/presentation/providers/discover_provider.dart';
import 'package:readtoon/presentation/providers/firestore_review_provider.dart';
import 'package:readtoon/presentation/providers/firestore_sync_provider.dart';
import 'package:readtoon/presentation/providers/library_provider.dart';
import 'package:readtoon/presentation/providers/reader_provider.dart';
import 'package:readtoon/presentation/providers/settings_provider.dart';
import 'package:readtoon/presentation/providers/tracked_series_provider.dart';
import 'package:readtoon/presentation/screens/auth_screen.dart';
import 'package:readtoon/presentation/screens/discover_screen.dart';
import 'package:readtoon/presentation/screens/profile_screen.dart';
import 'package:readtoon/presentation/screens/series_detail_screen.dart';

void main() {
  late Directory hiveDirectory;

  setUp(() async {
    _MemoryTrackedSeriesNotifier.savedSeries.clear();
    _MemoryFirestoreReviewService.savedReviews.clear();
    hiveDirectory = await Directory.systemTemp.createTemp('readtoon_test_');
    Hive.init(hiveDirectory.path);

    if (!Hive.isAdapterRegistered(AppConstants.comicBookTypeId)) {
      Hive.registerAdapter(ComicBookAdapter());
    }
    if (!Hive.isAdapterRegistered(AppConstants.readHistoryTypeId)) {
      Hive.registerAdapter(ReadHistoryAdapter());
    }
    if (!Hive.isAdapterRegistered(AppConstants.trackedSeriesTypeId)) {
      Hive.registerAdapter(TrackedSeriesAdapter());
    }

    await Future.wait([
      Hive.openBox<ComicBook>(AppConstants.comicsBox),
      Hive.openBox<ReadHistory>(AppConstants.historyBox),
      Hive.openBox<TrackedSeries>(AppConstants.trackedSeriesBox),
      Hive.openBox<dynamic>(AppConstants.settingsBox),
    ]);
  });

  tearDown(() async {
    await Hive.close();
    await hiveDirectory.delete(recursive: true);
  });

  testWidgets('signed-out launch offers guest access before setup', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: ReadToonApp()));
    await tester.pumpAndSettle();

    expect(find.text('ReadToon hesabı'), findsOneWidget);
    expect(find.text('Google ile Devam Et'), findsOneWidget);
    expect(find.text('Konuk Olarak Devam Et'), findsOneWidget);

    await tester.ensureVisible(find.text('Konuk Olarak Devam Et'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Konuk Olarak Devam Et'));
    await tester.pumpAndSettle();
    expect(find.text('Keşfet'), findsOneWidget);
    expect(find.textContaining('Henüz klasör yok'), findsOneWidget);
  });

  test(
    'settings persists multiple locations and an optional active location',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final settings = container.read(appSettingsProvider.notifier);

      await settings.addFolderPath('/library/comics');
      await settings.addFolderPath('/library/tbate');
      await settings.setSelectedFolderPath('/library/tbate');

      expect(container.read(appSettingsProvider).folderPaths, [
        '/library/comics',
        '/library/tbate',
      ]);
      expect(
        container.read(appSettingsProvider).selectedFolderPath,
        '/library/tbate',
      );
      expect(
        Hive.box<dynamic>(
          AppConstants.settingsBox,
        ).get(AppConstants.settingsKeyFolderPaths),
        ['/library/comics', '/library/tbate'],
      );

      await settings.setSelectedFolderPath(null);
      expect(container.read(appSettingsProvider).selectedFolderPath, isNull);
    },
  );

  test('removing a location deletes its comics and read history', () async {
    final folder = Directory('${hiveDirectory.path}/location_to_remove');
    await folder.create(recursive: true);
    final comic = ComicBook(
      id: 'location-comic',
      title: 'Location comic',
      filePath: '${folder.path}/chapter.cbz',
      totalPages: 10,
      parentFolderPath: folder.path,
      addedAt: DateTime.now(),
    );
    await Hive.box<ComicBook>(AppConstants.comicsBox).put(comic.id, comic);
    await Hive.box<ReadHistory>(AppConstants.historyBox).put(
      comic.id,
      ReadHistory(
        comicId: comic.id,
        currentPage: 3,
        readingMode: 'webtoon',
        lastReadAt: DateTime.now(),
      ),
    );

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container
        .read(appSettingsProvider.notifier)
        .addFolderPath(folder.path);
    await container
        .read(libraryProvider.notifier)
        .removeFolderPath(folder.path);

    expect(Hive.box<ComicBook>(AppConstants.comicsBox).get(comic.id), isNull);
    expect(
      Hive.box<ReadHistory>(AppConstants.historyBox).get(comic.id),
      isNull,
    );
    expect(container.read(appSettingsProvider).folderPaths, isEmpty);
  });

  test('library combines locations and filters the selected folder', () async {
    const firstFolder = '/library/comics';
    const secondFolder = '/library/tbate';
    for (final entry in [('comic-a', firstFolder), ('comic-b', secondFolder)]) {
      await Hive.box<ComicBook>(AppConstants.comicsBox).put(
        entry.$1,
        ComicBook(
          id: entry.$1,
          title: entry.$1,
          filePath: '${entry.$2}/${entry.$1}.cbz',
          totalPages: 10,
          parentFolderPath: entry.$2,
          addedAt: DateTime.now(),
        ),
      );
    }

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final settings = container.read(appSettingsProvider.notifier);
    await settings.addFolderPath(firstFolder);
    await settings.addFolderPath(secondFolder);
    await container.read(libraryProvider.future);

    expect(container.read(visibleLibraryProvider).valueOrNull, hasLength(2));
    await settings.setSelectedFolderPath(secondFolder);
    expect(
      container
          .read(visibleLibraryProvider)
          .valueOrNull
          ?.map((comic) => comic.id),
      ['comic-b'],
    );
  });

  test(
    'folder stats include size, groups, and completed reading history',
    () async {
      final folder = Directory('${hiveDirectory.path}/stats_library');
      final seriesFolder = Directory('${folder.path}/tbate');
      await seriesFolder.create(recursive: true);
      await File('${seriesFolder.path}/chapter.cbz').writeAsBytes([1, 2, 3, 4]);

      final completedComic = ComicBook(
        id: 'completed-stats-comic',
        title: 'Completed',
        filePath: '${seriesFolder.path}/chapter.cbz',
        totalPages: 2,
        parentFolderPath: folder.path,
        addedAt: DateTime.now(),
      );
      final unreadComic = ComicBook(
        id: 'unread-stats-comic',
        title: 'Unread',
        filePath: '${folder.path}/unread.cbz',
        totalPages: 4,
        parentFolderPath: folder.path,
        addedAt: DateTime.now(),
      );
      await Hive.box<ComicBook>(AppConstants.comicsBox).putAll({
        completedComic.id: completedComic,
        unreadComic.id: unreadComic,
      });
      await Hive.box<ReadHistory>(AppConstants.historyBox).put(
        completedComic.id,
        ReadHistory(
          comicId: completedComic.id,
          currentPage: 1,
          readingMode: 'webtoon',
          lastReadAt: DateTime.now(),
        ),
      );

      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container
          .read(appSettingsProvider.notifier)
          .addFolderPath(folder.path);
      final stats = await container.read(folderLibraryStatsProvider.future);

      expect(stats.single.totalBooks, 2);
      expect(stats.single.totalBytes, 4);
      expect(stats.single.seriesCount, 1);
      expect(stats.single.readBooks, 1);
      expect(stats.single.unreadBooks, 1);
    },
  );

  testWidgets('selected library exposes the four main navigation tabs', (
    tester,
  ) async {
    await tester.runAsync(
      () => Hive.box<dynamic>(
        AppConstants.settingsBox,
      ).put(AppConstants.settingsKeyFolderPath, hiveDirectory.path),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => Stream.value(
              const AuthenticatedUser(
                uid: 'navigation-test-user',
                email: 'reader@example.com',
                username: 'reader',
              ),
            ),
          ),
          firestoreSyncOnSignInProvider.overrideWith((ref) {}),
        ],
        child: const ReadToonApp(),
      ),
    );
    await tester.pump();

    expect(find.text('Kütüphane'), findsNWidgets(2));
    expect(find.text('Keşfet'), findsOneWidget);
    expect(find.text('Takip Listem'), findsOneWidget);
    expect(find.text('Profil'), findsOneWidget);
  });

  testWidgets('series detail displays rating, progress, and summary controls', (
    tester,
  ) async {
    const media = AniListMedia(
      id: 543,
      title: 'ReadToon test series',
      coverUrl: '',
      status: 'RELEASING',
      totalChapters: 52,
      averageScore: 87,
      description: 'A short test summary.',
      genres: ['Action', 'Drama'],
    );

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: SeriesDetailScreen(media: media)),
      ),
    );
    await tester.pump();

    expect(find.text('Seri Detayı'), findsOneWidget);
    expect(find.text('ReadToon test series'), findsOneWidget);
    expect(find.text('Devam Ediyor'), findsOneWidget);
    expect(find.text('0 / 52'), findsOneWidget);
    expect(find.text('İnceleme / Not ekle'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('A short test summary.'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('A short test summary.'), findsOneWidget);
  });

  testWidgets('auth screen switches between login and registration fields', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith((ref) => Stream.value(null)),
        ],
        child: const MaterialApp(home: AuthScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Şifremi unuttum'), findsOneWidget);
    expect(find.text('Kullanıcı adı'), findsNothing);

    await tester.tap(find.text('Kayıt Ol'));
    await tester.pumpAndSettle();

    expect(find.text('Kullanıcı adı'), findsOneWidget);
    expect(find.text('Hesap oluştur'), findsOneWidget);
  });

  testWidgets('series rating supports half-star drag input', (tester) async {
    const media = AniListMedia(
      id: 881,
      title: 'Rating drag test',
      coverUrl: '',
      totalChapters: 20,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trackedSeriesProvider.overrideWith(_MemoryTrackedSeriesNotifier.new),
          authStateProvider.overrideWith(
            (ref) => Stream.value(
              const AuthenticatedUser(
                uid: 'test-user',
                email: 'test@example.com',
                username: 'test_reader',
              ),
            ),
          ),
          firestoreReviewServiceProvider.overrideWithValue(
            _MemoryFirestoreReviewService(),
          ),
        ],
        child: const MaterialApp(home: SeriesDetailScreen(media: media)),
      ),
    );
    await tester.pump();

    final firstStar = find.byIcon(Icons.star_border_rounded).first;
    await tester.ensureVisible(firstStar);
    await tester.pumpAndSettle();
    final ratingGesture = find
        .ancestor(of: firstStar, matching: find.byType(GestureDetector))
        .first;
    final bounds = tester.getRect(ratingGesture);
    await tester.dragFrom(
      Offset(bounds.left + 2, bounds.center.dy),
      Offset(bounds.width * 0.88, 0),
    );
    await tester.pumpAndSettle();

    expect(_MemoryTrackedSeriesNotifier.savedSeries[media.id]?.rating, 4.5);
    expect(_MemoryFirestoreReviewService.savedReviews[media.id]?.rating, 4.5);
    expect(find.text('Başyapıt'), findsOneWidget);
  });

  testWidgets('community reviews show a live average and author details', (
    tester,
  ) async {
    const media = AniListMedia(
      id: 883,
      title: 'Community review test',
      coverUrl: '',
    );
    _MemoryFirestoreReviewService.savedReviews[media.id] = CommunityReview(
      userId: 'test-user',
      username: 'test_reader',
      rating: 4.5,
      reviewNote: 'A shared community review.',
      updatedAt: DateTime.utc(2025, 3, 4),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firestoreReviewServiceProvider.overrideWithValue(
            _MemoryFirestoreReviewService(),
          ),
        ],
        child: const MaterialApp(home: SeriesDetailScreen(media: media)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('@test_reader'),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('ReadToon Topluluk İncelemeleri'), findsOneWidget);
    expect(find.text('@test_reader'), findsOneWidget);
    expect(find.text('A shared community review.'), findsOneWidget);
    expect(find.text('4.5'), findsWidgets);
  });

  testWidgets('rating prompts unauthenticated users to sign in', (
    tester,
  ) async {
    const media = AniListMedia(
      id: 882,
      title: 'Sign-in gate test',
      coverUrl: '',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trackedSeriesProvider.overrideWith(_MemoryTrackedSeriesNotifier.new),
          authStateProvider.overrideWith((ref) => Stream.value(null)),
          firestoreReviewServiceProvider.overrideWithValue(
            _MemoryFirestoreReviewService(),
          ),
        ],
        child: const MaterialApp(home: SeriesDetailScreen(media: media)),
      ),
    );
    await tester.pumpAndSettle();

    final star = find.byIcon(Icons.star_border_rounded).first;
    await tester.ensureVisible(star);
    await tester.tap(star);
    await tester.pumpAndSettle();

    expect(find.text('ReadToon hesabı'), findsOneWidget);
    expect(_MemoryTrackedSeriesNotifier.savedSeries[media.id], isNull);
  });

  testWidgets(
    'chapter count can be entered directly and respects known total',
    (tester) async {
      const media = AniListMedia(
        id: 879,
        title: 'Chapter editor test',
        coverUrl: '',
        totalChapters: 52,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            trackedSeriesProvider.overrideWith(
              _MemoryTrackedSeriesNotifier.new,
            ),
            authStateProvider.overrideWith(
              (ref) => Stream.value(
                const AuthenticatedUser(
                  uid: 'chapter-test-user',
                  email: 'chapter@example.com',
                  username: 'chapter_reader',
                ),
              ),
            ),
          ],
          child: const MaterialApp(home: SeriesDetailScreen(media: media)),
        ),
      );
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('0 / 52'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('0 / 52'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('0 / 52'));
      await tester.pumpAndSettle();
      expect(find.text('Okunan bölüm sayısı'), findsOneWidget);

      await tester.enterText(find.byType(TextField).last, '53');
      await tester.tap(find.widgetWithText(FilledButton, 'Kaydet'));
      await tester.pumpAndSettle();
      expect(find.text('En fazla 52 bölüm okunmuş olabilir.'), findsOneWidget);

      await tester.enterText(find.byType(TextField).last, '18');
      await tester.tap(find.widgetWithText(FilledButton, 'Kaydet'));
      await tester.pumpAndSettle();

      expect(find.text('18 / 52'), findsOneWidget);
      expect(
        _MemoryTrackedSeriesNotifier.savedSeries[media.id]?.chaptersRead,
        18,
      );

      final progressSlider = find.byType(Slider);
      await tester.ensureVisible(progressSlider);
      await tester.pumpAndSettle();
      final sliderRect = tester.getRect(progressSlider);
      await tester.tapAt(
        Offset(sliderRect.left + sliderRect.width * 0.8, sliderRect.center.dy),
      );
      await tester.pumpAndSettle();
      expect(
        _MemoryTrackedSeriesNotifier.savedSeries[media.id]!.chaptersRead,
        greaterThan(18),
      );
    },
  );

  testWidgets('review bottom sheet saves a note for an untracked series', (
    tester,
  ) async {
    const media = AniListMedia(
      id: 880,
      title: 'Review editor test',
      coverUrl: '',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trackedSeriesProvider.overrideWith(_MemoryTrackedSeriesNotifier.new),
          authStateProvider.overrideWith(
            (ref) => Stream.value(
              const AuthenticatedUser(
                uid: 'test-user',
                email: 'test@example.com',
                username: 'test_reader',
              ),
            ),
          ),
          firestoreReviewServiceProvider.overrideWithValue(
            _MemoryFirestoreReviewService(),
          ),
        ],
        child: const MaterialApp(home: SeriesDetailScreen(media: media)),
      ),
    );
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('İnceleme / Not ekle'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('İnceleme / Not ekle'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('İnceleme / Not ekle'));
    await tester.pumpAndSettle();
    expect(find.text('İnceleme / Not'), findsOneWidget);
    await tester.tap(find.text('İptal'));
    await tester.pumpAndSettle();
    expect(find.text('İnceleme / Not'), findsNothing);

    await tester.tap(find.text('İnceleme / Not ekle'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'A thoughtful story.');
    await tester.tap(find.text('İncelemeyi Kaydet'));
    await tester.pumpAndSettle();

    final saved = _MemoryTrackedSeriesNotifier.savedSeries[media.id];
    expect(saved?.reviewNote, 'A thoughtful story.');
    expect(
      _MemoryFirestoreReviewService.savedReviews[media.id]?.reviewNote,
      'A thoughtful story.',
    );
    expect(saved?.status, TrackedSeriesStatus.planToRead);
    expect(tester.takeException(), isNull);
  });

  testWidgets('discover carousel arrow opens the category grid', (
    tester,
  ) async {
    final client = MockClient((request) async {
      return http.Response('{"data":{"Page":{"media":[]}}}', 200);
    });
    final service = AniListService(client: client);
    addTearDown(() {
      service.close();
      client.close();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [aniListServiceProvider.overrideWithValue(service)],
        child: const MaterialApp(home: DiscoverScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final seeAllButton = find.byTooltip('Tümünü gör: Trend Olanlar');
    expect(seeAllButton, findsOneWidget);
    await tester.tap(seeAllButton);
    await tester.pumpAndSettle();

    expect(find.text('Trend Olanlar'), findsOneWidget);
    expect(find.text('Şu anda gösterilecek seri yok.'), findsOneWidget);
  });

  test('TrackedSeries persists through its Hive adapter', () async {
    final box = Hive.box<TrackedSeries>(AppConstants.trackedSeriesBox);
    final series = TrackedSeries(
      mediaId: 123,
      title: 'Example manga',
      coverUrl: 'https://example.com/cover.jpg',
      status: TrackedSeriesStatus.reading,
      rating: 4.5,
      chaptersRead: 18,
      totalChapters: 52,
      reviewNote: 'Enjoying the story',
      updatedAt: DateTime.utc(2025, 1, 2),
      completedLocalComicIds: ['local-chapter-1'],
      isFavorite: true,
    );

    await box.put(series.mediaId, series);
    final restored = box.get(series.mediaId)!;

    expect(restored.mediaId, 123);
    expect(restored.status, TrackedSeriesStatus.reading);
    expect(restored.rating, 4.5);
    expect(restored.chaptersRead, 18);
    expect(restored.totalChapters, 52);
    expect(restored.reviewNote, 'Enjoying the story');
    expect(restored.completedLocalComicIds, ['local-chapter-1']);
    expect(restored.isFavorite, isTrue);
  });

  test('ComicBook persists its linked AniList media ID', () async {
    final box = Hive.box<ComicBook>(AppConstants.comicsBox);
    final comic = ComicBook(
      id: 'local-comic-1',
      title: 'Local chapter',
      filePath: '/library/chapter.cbz',
      totalPages: 20,
      parentFolderPath: '/library',
      addedAt: DateTime.utc(2025, 1, 2),
      linkedMediaId: 987,
    );

    await box.put(comic.id, comic);

    expect(box.get(comic.id)?.linkedMediaId, 987);
  });

  test(
    'local completion increments a tracked series only once per comic',
    () async {
      final box = Hive.box<TrackedSeries>(AppConstants.trackedSeriesBox);
      await box.put(
        987,
        TrackedSeries(
          mediaId: 987,
          title: 'Example series',
          coverUrl: '',
          chaptersRead: 1,
          totalChapters: 5,
        ),
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(trackedSeriesProvider.notifier);

      expect(
        await notifier.countLocalComicCompletion(
          mediaId: 987,
          comicId: 'local-comic-1',
        ),
        isTrue,
      );
      expect(
        await notifier.countLocalComicCompletion(
          mediaId: 987,
          comicId: 'local-comic-1',
        ),
        isFalse,
      );
      expect(box.get(987)?.chaptersRead, 2);
    },
  );

  test('reader completion increments its linked series once', () async {
    final trackedBox = Hive.box<TrackedSeries>(AppConstants.trackedSeriesBox);
    await trackedBox.put(
      987,
      TrackedSeries(
        mediaId: 987,
        title: 'Example series',
        coverUrl: '',
        totalChapters: 5,
      ),
    );
    final comic = ComicBook(
      id: 'reader-local-comic',
      title: 'Local chapter',
      filePath: '/library/chapter.cbz',
      totalPages: 3,
      parentFolderPath: '/library',
      addedAt: DateTime.now(),
      linkedMediaId: 987,
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final reader = container.read(currentPageProvider.notifier);

    reader.initialize(comic, AppConstants.readingModeManga);
    reader.goToPage(1);
    reader.goToPage(2);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(trackedBox.get(987)?.chaptersRead, 1);

    reader.goToPage(1);
    reader.goToPage(2);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(trackedBox.get(987)?.chaptersRead, 1);
  });

  testWidgets('profile shows Hive stats and recent diary activity', (
    tester,
  ) async {
    await tester.runAsync(
      () => Hive.box<TrackedSeries>(AppConstants.trackedSeriesBox).put(
        4321,
        TrackedSeries(
          mediaId: 4321,
          title: 'Profile test series',
          coverUrl: '',
          status: TrackedSeriesStatus.completed,
          rating: 4.5,
          chaptersRead: 24,
          totalChapters: 24,
          reviewNote: 'A memorable story.',
          updatedAt: DateTime.utc(2025, 6, 1),
        ),
      ),
    );

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: ProfileScreen())),
    );
    await tester.pump();

    expect(find.text('Bitirilen Seri'), findsOneWidget);
    expect(find.text('Okunan Bölüm'), findsOneWidget);
    expect(find.text('Ortalama Puan'), findsOneWidget);
    expect(find.text('24'), findsOneWidget);
    expect(find.text('4.5'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('A memorable story.'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Profile test series'), findsOneWidget);
    expect(find.text('A memorable story.'), findsOneWidget);
  });

  test('AniListMedia parses the API response and selects a readable title', () {
    final media = AniListMedia.fromJson({
      'id': 42,
      'title': {'romaji': 'Romaji title', 'english': 'English title'},
      'coverImage': {'large': 'https://example.com/cover.jpg'},
      'genres': ['Action', 'Drama'],
      'chapters': 52,
      'averageScore': 87,
    });

    expect(media.title, 'English title');
    expect(media.coverUrl, 'https://example.com/cover.jpg');
    expect(media.genres, ['Action', 'Drama']);
    expect(media.totalChapters, 52);
    expect(media.averageScore, 87);
  });

  test('TrackedSeries rating is clamped to half-star steps', () {
    final series = TrackedSeries(
      mediaId: 123,
      title: 'Example manga',
      coverUrl: '',
      rating: 4.3,
    );

    expect(series.rating, 4.5);
    series.rating = 7;
    expect(series.rating, 5);
    series.rating = -1;
    expect(series.rating, 0);
  });
}

class _MemoryFirestoreReviewService extends FirestoreReviewService {
  static final Map<int, CommunityReview> savedReviews = {};

  @override
  Stream<List<CommunityReview>> watchReviews(int mediaId) => Stream.value(
    savedReviews.values
        .where((review) => review.userId == 'test-user')
        .toList(),
  );

  @override
  Future<void> saveReview({
    required int mediaId,
    required double rating,
    required String? reviewNote,
  }) async {
    savedReviews[mediaId] = CommunityReview(
      userId: 'test-user',
      username: 'test_reader',
      rating: rating,
      reviewNote: reviewNote ?? '',
      updatedAt: DateTime.now(),
    );
  }
}

class _MemoryTrackedSeriesNotifier extends TrackedSeriesNotifier {
  static final Map<int, TrackedSeries> savedSeries = {};

  @override
  List<TrackedSeries> build() => const [];

  @override
  Future<void> save(TrackedSeries series) async {
    series.updatedAt = DateTime.now();
    savedSeries[series.mediaId] = series;
    state = [...state.where((item) => item.mediaId != series.mediaId), series];
  }
}
