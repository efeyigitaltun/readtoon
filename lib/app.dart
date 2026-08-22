import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'presentation/providers/settings_provider.dart';
import 'presentation/screens/library_screen.dart';
import 'presentation/screens/setup_screen.dart';

/// Uygulamanın kök widget'ı.
class ReadToonApp extends ConsumerWidget {
  const ReadToonApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'ReadToon',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const _RootNavigator(),
    );
  }
}

/// Klasör seçimi durumuna göre Setup veya Library ekranını gösterir.
class _RootNavigator extends ConsumerWidget {
  const _RootNavigator();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folderPath = ref.watch(appSettingsProvider).folderPath;

    if (folderPath == null) {
      return const SetupScreen();
    }

    return const LibraryScreen();
  }
}
