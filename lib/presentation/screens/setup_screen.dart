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
      // İzin kontrolü
      final permService = ref.read(permissionServiceProvider);
      final granted = await permService.requestStoragePermission();

      if (!granted && mounted) {
        final permanent = await permService.isPermanentlyDenied();
        _showPermissionDialog(permanentlyDenied: permanent);
        return;
      }
      if (!granted || !mounted) return;

      // Klasör seç
      final filePickerService = ref.read(filePickerServiceProvider);
      final path = await filePickerService.pickMangaDirectory();

      if (path != null && mounted) {
        await ref.read(appSettingsProvider.notifier).setFolderPath(path);
        await ref.read(libraryProvider.notifier).onFolderChanged(path);
      }
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  void _showPermissionDialog({required bool permanentlyDenied}) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
        title: const Text('Depolama İzni Gerekli',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          permanentlyDenied
              ? 'İzin kalıcı olarak reddedildi. '
                  'Uygulama ayarlarından "Tüm Dosyalara Erişim" iznini etkinleştirin.'
              : 'Manga dosyalarına erişmek için "Tüm Dosyalara Erişim" izni gereklidir. '
                  'Açılan Ayarlar ekranında izni etkinleştirin.',
          style: const TextStyle(color: AppColors.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await ref
                  .read(permissionServiceProvider)
                  .openAppPermissionSettings();
            },
            child: const Text('Ayarları Aç'),
          ),
        ],
      ),
    );
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
              const Icon(Icons.menu_book_rounded, size: 88, color: AppColors.accent),
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
              _PermissionInfoCard(),
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
                label: Text(_isWorking ? 'Lütfen bekleyin…' : 'Manga Klasörünü Seç'),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.info_outline_rounded,
                      size: 14, color: AppColors.textDisabled),
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

class _PermissionInfoCard extends StatelessWidget {
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
                  'Dosya İzni Gerekiyor',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Android 11+ cihazlarda "Tüm Dosyalara Erişim" iznine ihtiyaç vardır. '
                  'Butona bastıktan sonra açılan ekranda izni etkinleştirin.',
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
