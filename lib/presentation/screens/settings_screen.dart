import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../providers/settings_provider.dart';

/// General and reader preferences; library locations live on LibraryScreen.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Ayarlar')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          const _SectionTitle('GENEL'),
          Card(
            color: AppColors.cardBackground,
            child: Column(
              children: [
                _SettingsSwitch(
                  title: 'Açılışta kütüphaneyi tara',
                  subtitle: 'Uygulama açıldığında tüm lokasyonları tara',
                  value: settings.scanOnStartup,
                  onChanged: (value) => ref
                      .read(appSettingsProvider.notifier)
                      .setScanOnStartup(value),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const _SectionTitle('OKUYUCU'),
          Card(
            color: AppColors.cardBackground,
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
          const SizedBox(height: 16),
          const Center(
            child: Text(
              'Klasörlerini Kütüphane ekranındaki Locations bölümünden yönet.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textDisabled, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

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
  const _SettingsSwitch({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

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
