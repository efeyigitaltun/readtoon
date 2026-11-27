import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../providers/library_provider.dart';
import '../providers/settings_provider.dart';

/// Onboarding / Setup ekranı.
/// İlk açılışta veya klasör sıfırlandığında gösterilir.
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  bool _isWorking = false;

  Future<void> _pickFolder() async {
    if (_isWorking) return;
    setState(() => _isWorking = true);

    try {
      if (!mounted) return;

      // Klasör seçimi Android'de kalıcı SAF izni verir.
      final filePickerService = ref.read(filePickerServiceProvider);
      final path = await filePickerService.pickMangaDirectory();

      if (path != null && mounted) {
        await ref.read(libraryProvider.notifier).onFolderChanged(path);
      }
    } finally {
      if (mounted) setState(() => _isWorking = false);
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
              const Icon(
                Icons.menu_book_rounded,
                size: 88,
                color: AppColors.accent,
              ),
              const SizedBox(height: 24),
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
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
              ),
              const SizedBox(height: 40),
              _SafInfoCard(),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _isWorking ? null : _pickFolder,
                icon: _isWorking
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
                  _isWorking ? 'Lütfen bekleyin…' : 'Manga Klasörünü Seç',
                ),
              ),
              const SizedBox(height: 16),
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
                      '.cbz  .cbr  .zip  .rar  .pdf  desteklenir',
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

class _SafInfoCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Icon(Icons.lock_open_rounded, size: 20, color: AppColors.accent),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Klasör erişimi güvenli biçimde verilir',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Android’in sistem klasör seçicisi yalnızca seçtiğiniz klasöre erişim verir. '
                  'Bu erişim uygulama yeniden başlatıldığında da korunur.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
