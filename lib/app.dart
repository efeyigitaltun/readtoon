import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'presentation/providers/auth_provider.dart';
import 'presentation/providers/firestore_sync_provider.dart';
import 'presentation/providers/navigation_provider.dart';

import 'presentation/screens/auth_screen.dart';
import 'presentation/screens/discover_screen.dart';
import 'presentation/screens/library_screen.dart';
import 'presentation/screens/profile_screen.dart';

import 'presentation/screens/tracking_list_screen.dart';

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

/// Auth gate and first-run folder routing for the main app.
class _RootNavigator extends ConsumerWidget {
  const _RootNavigator();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(firestoreSyncOnSignInProvider);
    final authState = ref.watch(authStateProvider);
    final isGuest = ref.watch(guestModeProvider);

    if (authState.isLoading && !isGuest) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator(color: AppColors.accent)),
      );
    }

    if (authState.valueOrNull == null && !isGuest) {
      return const AuthScreen(isGate: true);
    }

    return const _MainNavigationShell();
  }
}

class _MainNavigationShell extends ConsumerStatefulWidget {
  const _MainNavigationShell();

  @override
  ConsumerState<_MainNavigationShell> createState() =>
      _MainNavigationShellState();
}

class _MainNavigationShellState extends ConsumerState<_MainNavigationShell> {
  final Set<int> _visitedTabs = {0};

  void _selectTab(int index) {
    ref.read(mainTabProvider.notifier).select(index);
    setState(() => _visitedTabs.add(index));
  }

  Widget _buildTab(int index) {
    if (!_visitedTabs.contains(index)) return const SizedBox.shrink();

    return switch (index) {
      0 => const LibraryScreen(),
      1 => const DiscoverScreen(),
      2 => const TrackingListScreen(),
      _ => const ProfileScreen(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = ref.watch(mainTabProvider);
    _visitedTabs.add(selectedIndex);

    return Scaffold(
      body: IndexedStack(
        index: selectedIndex,
        children: List<Widget>.generate(4, _buildTab),
      ),
      bottomNavigationBar: _PillNavigationBar(
        selectedIndex: selectedIndex,
        onSelected: _selectTab,
      ),
    );
  }
}

class _PillNavigationBar extends StatelessWidget {
  const _PillNavigationBar({
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const _items = <({IconData icon, String label})>[
    (icon: Icons.library_books_rounded, label: 'Kütüphane'),
    (icon: Icons.explore_rounded, label: 'Keşfet'),
    (icon: Icons.bookmarks_rounded, label: 'Takip Listem'),
    (icon: Icons.person_rounded, label: 'Profil'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 18,
            offset: Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
          child: Row(
            children: [
              for (var index = 0; index < _items.length; index++)
                Expanded(
                  child: _PillNavigationItem(
                    icon: _items[index].icon,
                    label: _items[index].label,
                    selected: selectedIndex == index,
                    onTap: () => onSelected(index),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PillNavigationItem extends StatelessWidget {
  const _PillNavigationItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            height: 56,
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.accent.withValues(alpha: 0.15)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: selected
                    ? AppColors.accent.withValues(alpha: 0.22)
                    : Colors.transparent,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: AppColors.accent.withValues(alpha: 0.09),
                        blurRadius: 14,
                        spreadRadius: 1,
                      ),
                    ]
                  : const [],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedScale(
                  scale: selected ? 1.06 : 1,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    icon,
                    size: 20,
                    color: selected
                        ? AppColors.accent
                        : AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected
                        ? AppColors.accent
                        : AppColors.textSecondary,
                    fontSize: 10,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
