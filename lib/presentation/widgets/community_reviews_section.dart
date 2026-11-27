import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/community_review.dart';
import '../providers/auth_provider.dart';
import '../providers/firestore_review_provider.dart';
import '../screens/auth_screen.dart';

class CommunityReviewsSection extends ConsumerWidget {
  const CommunityReviewsSection({required this.mediaId, super.key});

  final int mediaId;

  Future<void> _reportReview(
    BuildContext context,
    WidgetRef ref,
    CommunityReview review,
  ) async {
    var user = ref.read(authStateProvider).valueOrNull;
    if (user == null) {
      await Navigator.of(
        context,
      ).push<bool>(MaterialPageRoute<bool>(builder: (_) => const AuthScreen()));
      if (!context.mounted) return;
      user = ref.read(authStateProvider).valueOrNull;
    }
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bildirim için giriş yapmalısınız.')),
      );
      return;
    }
    if (review.userId == user.uid) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('İncelemeyi bildir'),
        content: const Text(
          'Bu incelemeyi topluluk kurallarına aykırı olduğu için bildirmek istiyor musunuz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Bildir'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref
          .read(firestoreReviewServiceProvider)
          .reportReview(
            mediaId: mediaId,
            review: review,
            reason: 'Topluluk kurallarına aykırı içerik',
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('İnceleme moderasyona bildirildi.')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bildirim gönderilemedi. Tekrar deneyin.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviewsAsync = ref.watch(communityReviewsProvider(mediaId));
    final currentUserId = ref.watch(authStateProvider).valueOrNull?.uid;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.forum_outlined,
                color: AppColors.accent,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'ReadToon Topluluk İncelemeleri',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          reviewsAsync.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(color: AppColors.accent),
              ),
            ),
            error: (error, stackTrace) => _CommunityMessage(
              icon: Icons.cloud_off_rounded,
              message: 'Topluluk incelemeleri şu anda yüklenemiyor.',
            ),
            data: (reviews) {
              final ratedReviews = reviews
                  .where((review) => review.rating > 0)
                  .toList(growable: false);
              final average = ratedReviews.isEmpty
                  ? null
                  : ratedReviews.fold<double>(
                          0,
                          (total, review) => total + review.rating,
                        ) /
                        ratedReviews.length;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _CommunitySummary(
                    average: average,
                    ratingCount: ratedReviews.length,
                    reviewCount: reviews.length,
                  ),
                  const SizedBox(height: 10),
                  if (reviews.isEmpty)
                    const _CommunityMessage(
                      icon: Icons.rate_review_outlined,
                      message:
                          'Henüz topluluk incelemesi yok. İlk yorumu sen yaz.',
                    )
                  else
                    ListView.builder(
                      itemCount: reviews.length,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemBuilder: (context, index) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _CommunityReviewCard(
                          review: reviews[index],
                          onReport: currentUserId == reviews[index].userId
                              ? null
                              : () =>
                                    _reportReview(context, ref, reviews[index]),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CommunitySummary extends StatelessWidget {
  const _CommunitySummary({
    required this.average,
    required this.ratingCount,
    required this.reviewCount,
  });

  final double? average;
  final int ratingCount;
  final int reviewCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          const Icon(Icons.star_rounded, color: AppColors.accent, size: 26),
          const SizedBox(width: 8),
          Text(
            average == null ? '—' : average!.toStringAsFixed(1),
            style: const TextStyle(
              color: AppColors.accent,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            '/ 5.0',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const Spacer(),
          Text(
            '$ratingCount puan • $reviewCount inceleme',
            textAlign: TextAlign.end,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _CommunityReviewCard extends StatelessWidget {
  const _CommunityReviewCard({required this.review, this.onReport});

  final CommunityReview review;
  final VoidCallback? onReport;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  review.username.isEmpty
                      ? 'R'
                      : review.username.substring(0, 1).toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '@${review.username}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      _formatDate(review.updatedAt),
                      style: const TextStyle(
                        color: AppColors.textDisabled,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              if (review.rating > 0) ...[
                const Icon(
                  Icons.star_rounded,
                  color: AppColors.accent,
                  size: 17,
                ),
                const SizedBox(width: 3),
                Text(
                  review.rating.toStringAsFixed(1),
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
              if (onReport != null)
                PopupMenuButton<String>(
                  tooltip: 'İnceleme seçenekleri',
                  onSelected: (value) {
                    if (value == 'report') onReport!();
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'report',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.flag_outlined),
                        title: Text('Yorumu bildir'),
                      ),
                    ),
                  ],
                  icon: const Icon(
                    Icons.more_horiz_rounded,
                    color: AppColors.textDisabled,
                    size: 20,
                  ),
                ),
            ],
          ),
          if (review.reviewNote.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              review.reviewNote,
              style: const TextStyle(
                color: AppColors.textSecondary,
                height: 1.45,
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CommunityMessage extends StatelessWidget {
  const _CommunityMessage({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppColors.textDisabled, size: 26),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDate(DateTime? date) {
  if (date == null) return 'Tarih bekleniyor';
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  return '$day.$month.${date.year}';
}
