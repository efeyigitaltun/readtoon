import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app.dart';
import 'core/constants/app_constants.dart';
import 'data/models/comic_book.dart';
import 'data/models/read_history.dart';
import 'data/models/tracked_series.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ─── Sistem UI Ayarları ───────────────────────────────────────────────────
  // OLED için tam şeffaf durum çubuğu
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF121212),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Uygulama yalnızca dikey modda çalışır
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // ─── Firebase Başlatma ────────────────────────────────────────────────────
  // Firebase yapılandırması eksikse yerel okuyucu yine açılabilsin.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (error) {
    debugPrint(
      'Firebase başlatılamadı; bulut özellikleri kullanılamayacak: $error',
    );
  }

  // ─── Hive Başlatma ────────────────────────────────────────────────────────
  await Hive.initFlutter();

  // TypeAdapter'ları kaydet (yalnızca bir kez kayıt edilir)
  if (!Hive.isAdapterRegistered(AppConstants.comicBookTypeId)) {
    Hive.registerAdapter(ComicBookAdapter());
  }
  if (!Hive.isAdapterRegistered(AppConstants.readHistoryTypeId)) {
    Hive.registerAdapter(ReadHistoryAdapter());
  }
  if (!Hive.isAdapterRegistered(AppConstants.trackedSeriesTypeId)) {
    Hive.registerAdapter(TrackedSeriesAdapter());
  }

  // Box'ları aç
  await Future.wait([
    Hive.openBox<ComicBook>(AppConstants.comicsBox),
    Hive.openBox<ReadHistory>(AppConstants.historyBox),
    Hive.openBox<TrackedSeries>(AppConstants.trackedSeriesBox),
    Hive.openBox<dynamic>(AppConstants.settingsBox),
  ]);

  // ─── Uygulamayı Başlat ────────────────────────────────────────────────────
  runApp(const ProviderScope(child: ReadToonApp()));
}
