import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/tracked_series.dart';
import '../providers/auth_provider.dart';
import '../providers/tracked_series_provider.dart';
import 'auth_screen.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final series = ref.watch(trackedSeriesProvider);
    final authState = ref.watch(authStateProvider);
    final completedCount = series
        .where((item) => item.status == TrackedSeriesStatus.completed)
        .length;
    final totalChaptersRead = series.fold<int>(
      0,
      (total, item) => total + item.chaptersRead,
    );
    final ratedSeries = series.where((item) => item.rating > 0).toList();
    final averageRating = ratedSeries.isEmpty
        ? null
        : ratedSeries.fold<double>(0, (total, item) => total + item.rating) /
              ratedSeries.length;
    final knownChapterTotal = series.fold<int>(
      0,
      (total, item) => total + (item.totalChapters ?? 0),
    );
    final overallProgress = knownChapterTotal == 0
        ? 0.0
        : (totalChaptersRead / knownChapterTotal).clamp(0.0, 1.0);
    final activities =
        series
            .where(
              (item) =>
                  item.rating > 0 ||
                  (item.reviewNote?.trim().isNotEmpty ?? false),
            )
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Profil')),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: _ProfileAccountCard(
                user: authState.valueOrNull,
                isLoading: authState.isLoading,
                onSignIn: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const AuthScreen()),
                  );
                },
                onSignOut: () async {
                  try {
                    await ref.read(authServiceProvider).signOut();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Oturum kapatıldı.')),
                      );
                    }
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Çıkış yapılamadı.')),
                      );
                    }
                  }
                },
                onDeleteAccount: () => _confirmAndDeleteAccount(
                  context,
                  ref,
                  authState.valueOrNull!,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              child: _ProfileHero(
                trackedSeriesCount: series.length,
                chaptersRead: totalChaptersRead,
                knownChapterTotal: knownChapterTotal,
                progress: overallProgress,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
              child: _ProfileStatsBento(
                completedCount: completedCount,
                chaptersRead: totalChaptersRead,
                averageRating: averageRating,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Row(
                children: [
                  const Icon(
                    Icons.auto_stories_rounded,
                    color: AppColors.accent,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Son aktiviteler',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Text(
                      '${activities.length} kayıt',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (activities.isEmpty)
            const SliverToBoxAdapter(child: _EmptyDiary())
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _DiaryActivityCard(series: activities[index]),
                  ),
                  childCount: activities.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> _confirmAndDeleteAccount(
  BuildContext context,
  WidgetRef ref,
  AuthenticatedUser user,
) async {
  final passwordController = TextEditingController();
  final needsPassword = user.providerIds.contains('password');
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('Hesap kalıcı olarak silinsin mi?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Buluttaki profilin, takip listen, puanların ve incelemelerin silinir. '
            'Bu işlem geri alınamaz. Cihazdaki indirilen dosyalar etkilenmez.',
          ),
          if (needsPassword) ...[
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Mevcut şifre'),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFE57373),
            foregroundColor: AppColors.background,
          ),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Hesabı Sil'),
        ),
      ],
    ),
  );
  final password = passwordController.text;
  passwordController.dispose();
  if (confirmed != true || !context.mounted) return;

  try {
    await ref
        .read(authServiceProvider)
        .deleteAccount(password: needsPassword ? password : null);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Hesabınız ve bulut verileriniz silindi.'),
        ),
      );
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Hesap silinemedi. Doğrulamayı yenileyip tekrar deneyin.',
          ),
        ),
      );
    }
  }
}

class _ProfileAccountCard extends StatelessWidget {
  const _ProfileAccountCard({
    required this.user,
    required this.isLoading,
    required this.onSignIn,
    required this.onSignOut,
    required this.onDeleteAccount,
  });

  final AuthenticatedUser? user;
  final bool isLoading;
  final VoidCallback onSignIn;
  final VoidCallback onSignOut;
  final VoidCallback onDeleteAccount;

  @override
  Widget build(BuildContext context) {
    final signedIn = user != null;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(15),
            ),
            child: isLoading
                ? const Padding(
                    padding: EdgeInsets.all(13),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.accent,
                    ),
                  )
                : Icon(
                    signedIn
                        ? Icons.person_rounded
                        : Icons.person_outline_rounded,
                    color: AppColors.accent,
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  signedIn ? user!.username : 'ReadToon hesabı',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  signedIn
                      ? user!.email
                      : 'Puanlarını ve incelemelerini eşitle',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (signedIn) ...[
            IconButton(
              tooltip: 'Hesabımı kalıcı olarak sil',
              onPressed: onDeleteAccount,
              icon: const Icon(Icons.delete_forever_outlined),
              color: const Color(0xFFE57373),
            ),
            IconButton(
              tooltip: 'Çıkış yap',
              onPressed: onSignOut,
              icon: const Icon(Icons.logout_rounded),
              color: AppColors.textSecondary,
            ),
          ] else
            FilledButton.tonal(
              onPressed: isLoading ? null : onSignIn,
              child: const Text('Giriş Yap'),
            ),
        ],
      ),
    );
  }
}

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({
    required this.trackedSeriesCount,
    required this.chaptersRead,
    required this.knownChapterTotal,
    required this.progress,
  });

  final int trackedSeriesCount;
  final int chaptersRead;
  final int knownChapterTotal;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final progressLabel = knownChapterTotal == 0
        ? 'İlerleme kaydı biriktikçe burada görünür'
        : '$chaptersRead / $knownChapterTotal bölüm';

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withValues(alpha: 0.06),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF223238),
                    Color(0xFF171B1D),
                    AppColors.cardBackground,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: -74,
            right: -44,
            child: Container(
              width: 190,
              height: 190,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.accent.withValues(alpha: 0.07),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.13),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.accent.withValues(alpha: 0.32),
                        ),
                      ),
                      child: const Icon(
                        Icons.person_rounded,
                        color: AppColors.accent,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'OKUMA PROFİLİ',
                            style: TextStyle(
                              color: AppColors.accent,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Okuma profilin',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.auto_awesome_rounded,
                      color: AppColors.accent,
                      size: 20,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$chaptersRead bölüm',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        height: 1,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 2),
                      child: Text(
                        'okundu',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 17),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'GENEL OKUMA İLERLEMESİ',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    Text(
                      knownChapterTotal == 0
                          ? '—'
                          : '${(progress * 100).round()}%',
                      style: const TextStyle(
                        color: AppColors.accent,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: Colors.white.withValues(alpha: 0.09),
                    color: AppColors.accent,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        progressLabel,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    Text(
                      '$trackedSeriesCount seri takipte',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileStatsBento extends StatelessWidget {
  const _ProfileStatsBento({
    required this.completedCount,
    required this.chaptersRead,
    required this.averageRating,
  });

  final int completedCount;
  final int chaptersRead;
  final double? averageRating;

  @override
  Widget build(BuildContext context) {
    final completed = _BentoStatCard(
      icon: Icons.check_circle_rounded,
      label: 'Bitirilen Seri',
      value: '$completedCount',
      subtitle: 'tamamlanan',
    );
    final chapters = _BentoStatCard(
      icon: Icons.menu_book_rounded,
      label: 'Okunan Bölüm',
      value: '$chaptersRead',
      subtitle: 'toplam',
    );
    final rating = _BentoStatCard(
      icon: Icons.star_rounded,
      label: 'Ortalama Puan',
      value: averageRating?.toStringAsFixed(1) ?? '—',
      subtitle: averageRating == null ? 'henüz puan yok' : '5 üzerinden',
      wide: true,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 620) {
          return Row(
            children: [
              Expanded(child: completed),
              const SizedBox(width: 12),
              Expanded(child: chapters),
              const SizedBox(width: 12),
              Expanded(child: rating),
            ],
          );
        }
        return Column(
          children: [
            Row(
              children: [
                Expanded(child: completed),
                const SizedBox(width: 12),
                Expanded(child: chapters),
              ],
            ),
            const SizedBox(height: 12),
            rating,
          ],
        );
      },
    );
  }
}

class _BentoStatCard extends StatelessWidget {
  const _BentoStatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.subtitle,
    this.wide = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final String subtitle;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: wide ? 108 : 132,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.accent.withValues(alpha: wide ? 0.2 : 0.1),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withValues(alpha: 0.035),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: wide
          ? Row(
              children: [
                _StatIcon(icon: icon),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(label, style: _statLabelStyle),
                      const SizedBox(height: 4),
                      Text(subtitle, style: _statSubtitleStyle),
                    ],
                  ),
                ),
                Text(value, style: _statValueStyle.copyWith(fontSize: 30)),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _StatIcon(icon: icon),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _statLabelStyle,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text(value, style: _statValueStyle),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _statSubtitleStyle,
                ),
              ],
            ),
    );
  }

  static const _statLabelStyle = TextStyle(
    color: AppColors.textSecondary,
    fontSize: 11,
    fontWeight: FontWeight.w600,
  );
  static const _statSubtitleStyle = TextStyle(
    color: AppColors.textDisabled,
    fontSize: 10,
  );
  static const _statValueStyle = TextStyle(
    color: AppColors.accent,
    fontSize: 27,
    fontWeight: FontWeight.w700,
    height: 1,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

class _StatIcon extends StatelessWidget {
  const _StatIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: AppColors.accent, size: 17),
    );
  }
}

class _DiaryActivityCard extends StatelessWidget {
  const _DiaryActivityCard({required this.series});

  final TrackedSeries series;

  @override
  Widget build(BuildContext context) {
    final hasReview = series.reviewNote?.trim().isNotEmpty ?? false;
    final date = _formatDate(series.updatedAt);
    final activityLabel = hasReview && series.rating > 0
        ? 'Puan verdi ve not ekledi'
        : hasReview
        ? 'Günlüğüne not ekledi'
        : 'Seriyi puanladı';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DiaryCover(url: series.coverUrl),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  series.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$activityLabel · $date',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
                if (series.rating > 0) ...[
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      const Icon(
                        Icons.star_rounded,
                        color: AppColors.accent,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${series.rating.toStringAsFixed(1)} / 5',
                        style: const TextStyle(
                          color: AppColors.accent,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
                if (hasReview) ...[
                  const SizedBox(height: 6),
                  Text(
                    series.reviewNote!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      height: 1.35,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dateTime) {
    final local = dateTime.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    return '$day.$month.${local.year}';
  }
}

class _DiaryCover extends StatelessWidget {
  const _DiaryCover({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: SizedBox(
        width: 56,
        height: 78,
        child: url.isEmpty
            ? const ColoredBox(
                color: AppColors.surface,
                child: Icon(
                  Icons.auto_stories_rounded,
                  color: AppColors.accent,
                ),
              )
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => const ColoredBox(
                  color: AppColors.surface,
                  child: Icon(Icons.broken_image_outlined),
                ),
              ),
      ),
    );
  }
}

class _EmptyDiary extends StatelessWidget {
  const _EmptyDiary();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 40),
      child: Column(
        children: [
          const Icon(
            Icons.rate_review_outlined,
            size: 44,
            color: AppColors.textDisabled,
          ),
          const SizedBox(height: 12),
          Text(
            'Henüz aktivite yok',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Bir seriye puan verdiğinde veya not eklediğinde burada görünecek.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
