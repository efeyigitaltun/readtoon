import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:readtoon/app.dart';
import 'package:readtoon/core/constants/app_constants.dart';
import 'package:readtoon/data/models/comic_book.dart';
import 'package:readtoon/data/models/read_history.dart';

void main() {
  late Directory hiveDirectory;

  setUp(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('readtoon_test_');
    Hive.init(hiveDirectory.path);

    if (!Hive.isAdapterRegistered(AppConstants.comicBookTypeId)) {
      Hive.registerAdapter(ComicBookAdapter());
    }
    if (!Hive.isAdapterRegistered(AppConstants.readHistoryTypeId)) {
      Hive.registerAdapter(ReadHistoryAdapter());
    }

    await Future.wait([
      Hive.openBox<ComicBook>(AppConstants.comicsBox),
      Hive.openBox<ReadHistory>(AppConstants.historyBox),
      Hive.openBox<dynamic>(AppConstants.settingsBox),
    ]);
  });

  tearDown(() async {
    await Hive.close();
    await hiveDirectory.delete(recursive: true);
  });

  testWidgets('ReadToon opens setup when no library folder is selected', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: ReadToonApp()));
    await tester.pumpAndSettle();

    expect(find.text('ReadToon'), findsOneWidget);
    expect(find.text('Manga Klasörünü Seç'), findsOneWidget);
  });
}
