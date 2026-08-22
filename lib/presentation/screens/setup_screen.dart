import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../providers/library_provider.dart';
import '../providers/settings_provider.dart';

/// Onboarding / Setup ekranı.
/// Kullanıcı manga klasörünü ilk kez seçtiğinde veya klasör sıfırlandığında gösterilir.
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  bool _isPickingFolder = false;

  Future<void> _pickFolder() async {
    setState(() => _isPickingFolder = true);

    try {
      final folderNotifier = ref.read(selectedFolderProvider.notifier);
      final selectedPath = await folderNotifier.pickFolder();

      if (selectedPath != null && mounted) {
        // Klasör seçildi → kütüphaneyi tara
        await ref.read(libraryProvider.notifier).onFolderChanged(selectedPath);
      }
    } finally {
      if (mounted) setState(() => _isPickingFolder = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ─── Logo / İkon ──────────────────────────────────────────────
              const Icon(
                Icons.menu_book_rounded,
                size: 88,
                color: AppColors.accent,
              ),
              const SizedBox(height: 24),

              // ─── Başlık ───────────────────────────────────────────────────
              Text(
                'ReadToon',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Manga ve webtoon klasörünü seç,\nkütüphanen otomatik oluşsun.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 48),

              // ─── Klasör Seçim Butonu ──────────────────────────────────────
              ElevatedButton.icon(
                onPressed: _isPickingFolder ? null : _pickFolder,
                icon: _isPickingFolder
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.background,
                        ),
                      )
                    : const Icon(Icons.folder_open_rounded),
                label: Text(
                  _isPickingFolder ? 'Klasör seçiliyor…' : 'Manga Klasörünü Seç',
                ),
              ),
              const SizedBox(height: 16),

              // ─── Açıklama ─────────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 14,
                    color: AppColors.textDisabled,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '.cbz formatındaki dosyalar desteklenir',
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
