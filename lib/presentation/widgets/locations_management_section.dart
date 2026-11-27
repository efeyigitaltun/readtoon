import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/folder_library_stats.dart';

import '../providers/library_provider.dart';
import '../providers/navigation_provider.dart';
import '../providers/settings_provider.dart';

/// Home-screen location switcher and folder management controls.
class LocationsManagementSection extends ConsumerStatefulWidget {
  const LocationsManagementSection({super.key});

  @override
  ConsumerState<LocationsManagementSection> createState() =>
      _LocationsManagementSectionState();
}

class _LocationsManagementSectionState
    extends ConsumerState<LocationsManagementSection> {
  bool _isPickingFolder = false;
  bool _isExpanded = false;
  final Set<String> _scanningPaths = {};

  Future<void> _addFolder() async {
    if (_isPickingFolder) return;
    setState(() => _isPickingFolder = true);

    try {
      final path = await ref
          .read(filePickerServiceProvider)
          .pickMangaDirectory();
      if (path == null || !mounted) return;

      final alreadyAdded = ref
          .read(appSettingsProvider)
          .folderPaths
          .contains(path);
      await ref.read(appSettingsProvider.notifier).addFolderPath(path);
      if (!mounted) return;
      if (alreadyAdded) {
        _showMessage('Bu klasör zaten Locations listesinde.');
        return;
      }

      _showMessage('Klasör eklendi, tarama başlatıldı.');
      unawaited(_scanFolder(path));
    } catch (error) {
      if (mounted) _showMessage('Klasör eklenemedi: $error');
    } finally {
      if (mounted) setState(() => _isPickingFolder = false);
    }
  }

  Future<void> _scanFolder(String path) async {
    if (_scanningPaths.contains(path)) return;
    setState(() => _scanningPaths.add(path));
    try {
      await ref.read(libraryProvider.notifier).scanFolder(path);
      if (mounted) {
        _showMessage(
          '${FolderLibraryStats.nameFromPath(path)} taraması tamamlandı.',
        );
      }
    } catch (error) {
      if (mounted) _showMessage('Klasör taranamadı: $error');
    } finally {
      if (mounted) setState(() => _scanningPaths.remove(path));
    }
  }

  Future<void> _removeFolder(String path) async {
    final shouldRemove = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Lokasyon kaldırılsın mı?'),
        content: Text(
          '“${FolderLibraryStats.nameFromPath(path)}” klasörü listeden kaldırılacak. '
          'Bu klasöre ait kitaplar ve okuma geçmişi cihaz kütüphanesinden silinir. '
          'Dosyaların kendisi etkilenmez.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Kaldır'),
          ),
        ],
      ),
    );
    if (shouldRemove != true || !mounted) return;

    try {
      await ref.read(libraryProvider.notifier).removeFolderPath(path);
      if (mounted) {
        _showMessage(
          '${FolderLibraryStats.nameFromPath(path)} lokasyonu kaldırıldı.',
        );
      }
    } catch (error) {
      if (mounted) _showMessage('Lokasyon kaldırılamadı: $error');
    }
  }

  Future<void> _openFolder(String path) async {
    await ref.read(appSettingsProvider.notifier).setSelectedFolderPath(path);
    ref.read(mainTabProvider.notifier).select(0);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final statsAsync = ref.watch(folderLibraryStatsProvider);
    final statsByPath = {
      for (final stats in statsAsync.valueOrNull ?? <FolderLibraryStats>[])
        stats.folderPath: stats,
    };

    final activePath = settings.selectedFolderPath;
    final activeName = activePath == null
        ? 'Tüm klasörler'
        : statsByPath[activePath]?.folderName ??
              FolderLibraryStats.nameFromPath(activePath);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Material(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            children: [
              Semantics(
                button: true,
                expanded: _isExpanded,
                label: 'Klasörler, ${settings.folderPaths.length}. $activeName',
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => setState(() => _isExpanded = !_isExpanded),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 5, 6, 5),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.folder_copy_rounded,
                          color: AppColors.accent,
                          size: 19,
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            'Klasörler (${settings.folderPaths.length}) • Aktif: $activeName',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Klasör ekle',
                          visualDensity: VisualDensity.compact,
                          onPressed: _isPickingFolder ? null : _addFolder,
                          icon: _isPickingFolder
                              ? const SizedBox.square(
                                  dimension: 17,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.add_rounded),
                          color: AppColors.accent,
                        ),
                        AnimatedRotation(
                          turns: _isExpanded ? 0.5 : 0,
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          child: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                    ),
                  ),
                ),
              ),
              AnimatedCrossFade(
                firstChild: const SizedBox(width: double.infinity, height: 0),
                secondChild: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                  child: settings.folderPaths.isEmpty
                      ? _EmptyLocationsCard(onAdd: _addFolder)
                      : SizedBox(
                          height: 145,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: settings.folderPaths.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(width: 10),
                            itemBuilder: (context, index) {
                              final path = settings.folderPaths[index];
                              return _LocationCard(
                                path: path,
                                stats: statsByPath[path],
                                isSelected: settings.selectedFolderPath == path,
                                isScanning: _scanningPaths.contains(path),
                                onTap: () => _openFolder(path),
                                onScan: () => _scanFolder(path),
                                onRemove: () => _removeFolder(path),
                              );
                            },
                          ),
                        ),
                ),
                crossFadeState: _isExpanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 240),
                sizeCurve: Curves.easeOutCubic,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({
    required this.path,
    required this.stats,
    required this.isSelected,
    required this.isScanning,
    required this.onTap,
    required this.onScan,
    required this.onRemove,
  });

  final String path;
  final FolderLibraryStats? stats;
  final bool isSelected;
  final bool isScanning;
  final VoidCallback onTap;
  final VoidCallback onScan;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final folderName =
        stats?.folderName ?? FolderLibraryStats.nameFromPath(path);
    return SizedBox(
      width: 292,
      child: Material(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected
                    ? AppColors.accent.withValues(alpha: 0.64)
                    : AppColors.divider,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Icon(
                        Icons.folder_rounded,
                        color: AppColors.accent,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        folderName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    if (isSelected)
                      const Padding(
                        padding: EdgeInsets.only(right: 2),
                        child: Icon(
                          Icons.check_circle_rounded,
                          size: 16,
                          color: AppColors.accent,
                        ),
                      ),
                    PopupMenuButton<String>(
                      tooltip: 'Lokasyon seçenekleri',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 44),
                      onSelected: (value) {
                        if (value == 'scan') onScan();
                        if (value == 'remove') onRemove();
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'scan',
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.refresh_rounded),
                            title: Text('Yeniden tara'),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'remove',
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.delete_outline_rounded),
                            title: Text('Lokasyonu kaldır'),
                          ),
                        ),
                      ],
                      icon: isScanning
                          ? const SizedBox.square(
                              dimension: 17,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.more_vert_rounded, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  stats == null
                      ? (isScanning
                            ? 'Taranıyor…'
                            : 'İstatistikler hesaplanıyor…')
                      : '${stats!.totalBooks} kitap  •  ${stats!.totalSizeFormatted}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF9E9E9E),
                    fontSize: 11,
                  ),
                ),
                const Spacer(),
                Row(
                  children: [
                    _MicroStat(
                      icon: Icons.library_books_outlined,
                      value: stats?.seriesCount ?? 0,
                      label: 'Seri',
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 13),
                    _MicroStat(
                      icon: Icons.menu_book_rounded,
                      value: stats?.readBooks ?? 0,
                      label: 'Okunan',
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 13),
                    _MicroStat(
                      icon: Icons.visibility_outlined,
                      value: stats?.unreadBooks ?? 0,
                      label: 'Kalan',
                      color: AppColors.accent,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MicroStat extends StatelessWidget {
  const _MicroStat({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final int value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label: $value',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 3),
          Text(
            '$value',
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyLocationsCard extends StatelessWidget {
  const _EmptyLocationsCard({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.cardBackground,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onAdd,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.divider),
          ),
          child: const Row(
            children: [
              Icon(Icons.folder_open_rounded, color: AppColors.accent),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Henüz klasör yok. Kütüphaneni oluşturmak için klasör ekle.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
              Icon(Icons.add_rounded, color: AppColors.accent),
            ],
          ),
        ),
      ),
    );
  }
}
