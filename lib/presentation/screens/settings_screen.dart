import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/services/permission_service.dart';
import '../providers/library_provider.dart';
import '../providers/settings_provider.dart';

/// Hive/Riverpod ile kalıcı uygulama ayarları.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _changingFolder = false;

  Future<void> _changeFolder() async {
    if (_changingFolder) return;
    setState(() => _changingFolder = true);

    try {
      final permissions = ref.read(permissionServiceProvider);
      final granted = await permissions.requestStoragePermission();
      if (!granted) {
        if (mounted) _showPermissionRequiredDialog(permissions);
        return;
      }

      final filePicker = ref.read(filePickerServiceProvider);
      final path = await filePicker.pickMangaDirectory();
      if (path == null || !mounted) return;

      await ref.read(appSettingsProvider.notifier).setFolderPath(path);
      await ref.read(libraryProvider.notifier).onFolderChanged(path);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kütüphane klasörü güncellendi')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Klasör değiştirilemedi: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _changingFolder = false);
    }
  }

  void _showPermissionRequiredDialog(PermissionService permissions) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Depolama izni gerekli'),
        content: const Text(
          'Kütüphane klasörünü değiştirmek için depolama izni gereklidir. '
          'İzni uygulama ayarlarından etkinleştirebilirsiniz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              permissions.openAppPermissionSettings();
            },
            child: const Text('Ayarları Aç'),
          ),
        ],
      ),
    );
  }

  Future<void> _openPermissionSettings() async {
    await ref.read(permissionServiceProvider).openAppPermissionSettings();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Ayarlar')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const _SectionTitle('LOCATIONS'),
          Card(
            child: ListTile(
              leading: const Icon(
                Icons.folder_rounded,
                color: AppColors.accent,
              ),
              title: const Text('Kütüphane klasörü'),
              subtitle: Text(
                settings.folderPath ?? 'Klasör seçilmedi',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: _changingFolder
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right_rounded),
              onTap: _changingFolder ? null : _changeFolder,
            ),
          ),
          const SizedBox(height: 24),

          const _SectionTitle('GENERAL'),
          Card(
            child: Column(
              children: [
                FutureBuilder<bool>(
                  future: ref
                      .read(permissionServiceProvider)
                      .isStoragePermissionGranted(),
                  builder: (context, snapshot) {
                    final granted = snapshot.data ?? false;
                    return ListTile(
                      leading: Icon(
                        granted
                            ? Icons.lock_open_rounded
                            : Icons.lock_outline_rounded,
                        color: granted
                            ? AppColors.accent
                            : AppColors.textSecondary,
                      ),
                      title: const Text('Tüm dosyalara erişim'),
                      subtitle: Text(
                        snapshot.connectionState == ConnectionState.waiting
                            ? 'İzin durumu kontrol ediliyor…'
                            : granted
                            ? 'İzin verilmiş'
                            : 'İzin durumu: verilmemiş',
                      ),
                      trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                      onTap: _openPermissionSettings,
                    );
                  },
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                _SettingsSwitch(
                  title: 'Açılışta kütüphaneyi tara',
                  subtitle: 'Uygulama açıldığında seçili klasörü tara',
                  value: settings.scanOnStartup,
                  onChanged: (value) => ref
                      .read(appSettingsProvider.notifier)
                      .setScanOnStartup(value),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          const _SectionTitle('READER'),
          Card(
            child: Column(
              children: [
                _SettingsSwitch(
                  title: 'Ekranı açık tut',
                  subtitle: 'Okuma sırasında ekranın kapanmasını engelle',
                  value: settings.keepScreenOn,
                  onChanged: (value) => ref
                      .read(appSettingsProvider.notifier)
                      .setKeepScreenOn(value),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                _SettingsSwitch(
                  title: 'Dikey okuma modu',
                  subtitle: 'Webtoon sayfalarını dikey olarak kaydır',
                  value: settings.isWebtoonMode,
                  onChanged: (value) => ref
                      .read(appSettingsProvider.notifier)
                      .setWebtoonMode(value),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                _SettingsSwitch(
                  title: 'Sağdan sola okuma',
                  subtitle: 'Manga yönü (RTL); kapalıyken soldan sağa',
                  value: settings.isRTL,
                  onChanged: (value) =>
                      ref.read(appSettingsProvider.notifier).setRTL(value),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                _SettingsSwitch(
                  title: 'Çift dokunarak yakınlaştır',
                  subtitle: 'Okuma sırasında çift dokunuşla zoom yap',
                  value: settings.doubleTapZoom,
                  onChanged: (value) => ref
                      .read(appSettingsProvider.notifier)
                      .setDoubleTapZoom(value),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: AppColors.accent,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _SettingsSwitch extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsSwitch({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      activeTrackColor: AppColors.accent,
      activeThumbColor: AppColors.background,
      onChanged: onChanged,
    );
  }
}
