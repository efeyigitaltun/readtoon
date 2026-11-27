import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/anilist_media.dart';
import '../../data/models/tracked_series.dart';
import '../providers/auth_provider.dart';
import '../providers/firestore_review_provider.dart';
import '../providers/tracked_series_provider.dart';
import '../widgets/community_reviews_section.dart';
import '../widgets/shimmer_loading.dart';
import 'auth_screen.dart';

class SeriesDetailScreen extends ConsumerStatefulWidget {
  const SeriesDetailScreen({required this.media, super.key});

  final AniListMedia media;

  @override
  ConsumerState<SeriesDetailScreen> createState() => _SeriesDetailScreenState();
}

class _SeriesDetailScreenState extends ConsumerState<SeriesDetailScreen> {
  bool _descriptionExpanded = false;
  double? _chapterProgressPreview;

  AniListMedia get _media => widget.media;

  TrackedSeries? _trackedSeries(List<TrackedSeries> items) {
    for (final item in items) {
      if (item.mediaId == _media.id) return item;
    }
    return null;
  }

  TrackedSeries _newTrackedSeries() => TrackedSeries(
    mediaId: _media.id,
    title: _media.title,
    coverUrl: _media.coverUrl,
    bannerUrl: _media.bannerUrl,
    totalChapters: _media.totalChapters,
  );

  Future<void> _updateTracked(void Function(TrackedSeries) update) async {
    final notifier = ref.read(trackedSeriesProvider.notifier);
    final series = notifier.findByMediaId(_media.id) ?? _newTrackedSeries();
    series
      ..title = _media.title
      ..coverUrl = _media.coverUrl
      ..bannerUrl = _media.bannerUrl;
    if (_media.totalChapters != null) {
      series.totalChapters = _media.totalChapters;
    }
    update(series);

    try {
      await notifier.save(series);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Değişiklik kaydedilemedi.')),
      );
    }
  }

  Future<bool> _requireSignIn() async {
    var user = ref.read(authStateProvider).valueOrNull;
    if (user == null && ref.read(authStateProvider).isLoading) {
      try {
        user = await ref.read(authStateProvider.future);
      } catch (_) {
        user = null;
      }
    }
    if (user != null) return true;
    if (!mounted) return false;

    final didSignIn = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute<bool>(builder: (_) => const AuthScreen()));
    if (!mounted) return false;
    return ref.read(authStateProvider).valueOrNull != null ||
        (didSignIn == true && !ref.read(guestModeProvider));
  }

  Future<void> _setRating(double rating) async {
    if (!await _requireSignIn()) return;
    await _updateTracked((series) => series.rating = rating);
    final series = ref
        .read(trackedSeriesProvider.notifier)
        .findByMediaId(_media.id);
    if (series != null) await _syncReviewToCloud(series);
  }

  Future<void> _syncReviewToCloud(TrackedSeries series) async {
    try {
      await ref
          .read(firestoreReviewServiceProvider)
          .saveReview(
            mediaId: series.mediaId,
            rating: series.rating,
            reviewNote: series.reviewNote,
          );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Cihaza kaydedildi; toplulukla eşitlenemedi. Bağlantınızı kontrol edin.',
          ),
        ),
      );
    }
  }

  Future<void> _editReview(TrackedSeries? current) async {
    final signedIn = await _requireSignIn();
    if (!mounted || !signedIn) return;

    final note = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      builder: (sheetContext) => _ReviewEditorSheet(
        title: _media.title,
        initialNote: current?.reviewNote ?? '',
        rating: current?.rating ?? 0,
      ),
    );

    if (!mounted || note == null) return;
    await _updateTracked((series) {
      final trimmedNote = note.trim();
      series.reviewNote = trimmedNote.isEmpty ? null : trimmedNote;
    });
    final updated = ref
        .read(trackedSeriesProvider.notifier)
        .findByMediaId(_media.id);
    if (updated != null) await _syncReviewToCloud(updated);
  }

  Future<void> _changeStatus(TrackedSeriesStatus status) async {
    if (!await _requireSignIn()) return;
    await _updateTracked((series) => series.status = status);
  }

  Future<void> _changeChapterCount(int delta) async {
    if (!await _requireSignIn()) return;
    await _updateTracked((series) {
      final next = (series.chaptersRead + delta).clamp(0, 1 << 30);
      final total = series.totalChapters;
      series.chaptersRead = total == null ? next : next.clamp(0, total);
    });
  }

  Future<void> _setChapterProgress(double value) async {
    if (mounted) setState(() => _chapterProgressPreview = null);
    if (!await _requireSignIn()) return;
    final total =
        _trackedSeries(ref.read(trackedSeriesProvider))?.totalChapters ??
        _media.totalChapters;
    final chapterCount = value.round().clamp(0, total ?? (1 << 30)).toInt();
    await _updateTracked((series) => series.chaptersRead = chapterCount);
  }

  Future<void> _toggleFavorite() async {
    if (!await _requireSignIn()) return;
    await _updateTracked((series) => series.isFavorite = !series.isFavorite);
  }

  Future<void> _editChapterCount(int current, int? total) async {
    if (!await _requireSignIn() || !mounted) return;
    final chapterCount = await showDialog<int>(
      context: context,
      builder: (dialogContext) =>
          _ChapterCountDialog(initialValue: current, totalChapters: total),
    );
    if (!mounted || chapterCount == null) return;
    await _updateTracked((series) => series.chaptersRead = chapterCount);
  }

  @override
  Widget build(BuildContext context) {
    final allTrackedSeries = ref.watch(trackedSeriesProvider);
    final tracked = _trackedSeries(allTrackedSeries);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Seri Detayı'),
        leading: IconButton(
          tooltip: 'Geri',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        actions: [
          IconButton(
            tooltip: tracked?.isFavorite == true
                ? 'Favorilerden çıkar'
                : 'Favorilere ekle',
            onPressed: () => unawaited(_toggleFavorite()),
            icon: Icon(
              tracked?.isFavorite == true
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              color: tracked?.isFavorite == true
                  ? AppColors.accent
                  : AppColors.textSecondary,
            ),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _SeriesHero(media: _media)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
              child: _QuickActionsCard(
                media: _media,
                tracked: tracked,
                onStatusChanged: (status) => unawaited(_changeStatus(status)),
                onRatingChanged: (rating) => unawaited(_setRating(rating)),
                onChapterChanged: (delta) =>
                    unawaited(_changeChapterCount(delta)),
                chapterProgressPreview: _chapterProgressPreview,
                onChapterProgressChanged: (value) =>
                    setState(() => _chapterProgressPreview = value),
                onChapterProgressEnd: (value) =>
                    unawaited(_setChapterProgress(value)),
                onEditChapterCount: () => unawaited(
                  _editChapterCount(
                    tracked?.chaptersRead ?? 0,
                    tracked?.totalChapters ?? _media.totalChapters,
                  ),
                ),
                onEditReview: () => _editReview(tracked),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
              child: Text(
                'Özet',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ),
          SliverToBoxAdapter(child: _buildDescription(context)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
              child: Text(
                'Türler',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ),
          SliverToBoxAdapter(child: _buildGenres()),
          if (tracked?.reviewNote case final note? when note.isNotEmpty)
            SliverToBoxAdapter(child: _ReviewNoteCard(note: note)),
          SliverToBoxAdapter(
            child: CommunityReviewsSection(mediaId: _media.id),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  Widget _buildDescription(BuildContext context) {
    final description = _media.description?.trim();
    if (description == null || description.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          'Bu seri için özet bulunmuyor.',
          style: TextStyle(color: AppColors.textSecondary, height: 1.5),
        ),
      );
    }

    final canExpand = description.length > 320;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            description,
            maxLines: _descriptionExpanded ? null : 6,
            overflow: _descriptionExpanded
                ? TextOverflow.visible
                : TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textSecondary,
              height: 1.55,
              fontSize: 14,
            ),
          ),
          if (canExpand)
            TextButton(
              onPressed: () =>
                  setState(() => _descriptionExpanded = !_descriptionExpanded),
              child: Text(
                _descriptionExpanded ? 'Daha az göster' : 'Devamını oku',
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGenres() {
    if (_media.genres.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          'Tür bilgisi bulunmuyor.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final genre in _media.genres)
            Chip(
              label: Text(genre),
              backgroundColor: AppColors.surface,
              side: const BorderSide(color: AppColors.divider),
              labelStyle: const TextStyle(color: AppColors.textPrimary),
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}

class _ChapterCountDialog extends StatefulWidget {
  const _ChapterCountDialog({
    required this.initialValue,
    required this.totalChapters,
  });

  final int initialValue;
  final int? totalChapters;

  @override
  State<_ChapterCountDialog> createState() => _ChapterCountDialogState();
}

class _ChapterCountDialogState extends State<_ChapterCountDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue.toString(),
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = int.tryParse(_controller.text);
    if (value == null) {
      setState(() => _error = 'Geçerli bir bölüm numarası gir.');
      return;
    }
    final total = widget.totalChapters;
    if (total != null && value > total) {
      setState(() => _error = 'En fazla $total bölüm okunmuş olabilir.');
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('Okunan bölüm sayısı'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onSubmitted: (_) => _submit(),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        decoration: InputDecoration(
          labelText: 'Bölüm',
          hintText: 'Örn. 150',
          errorText: _error,
          helperText: widget.totalChapters == null
              ? 'Okuduğun son bölüm numarasını gir.'
              : 'Toplam ${widget.totalChapters} bölüm.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('İptal'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Kaydet')),
      ],
    );
  }
}

class _ReviewEditorSheet extends StatefulWidget {
  const _ReviewEditorSheet({
    required this.title,
    required this.initialNote,
    required this.rating,
  });

  final String title;
  final String initialNote;
  final double rating;

  @override
  State<_ReviewEditorSheet> createState() => _ReviewEditorSheetState();
}

class _ReviewEditorSheetState extends State<_ReviewEditorSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialNote,
  );
  int _characterCount = 0;

  @override
  void initState() {
    super.initState();
    _characterCount = widget.initialNote.length;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: SafeArea(
        top: false,
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.textDisabled,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'İnceleme / Not',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Kapat',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.cardBackground,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 56,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: const Icon(
                          Icons.auto_stories_rounded,
                          color: AppColors.accent,
                          size: 21,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Row(
                              children: [
                                const Icon(
                                  Icons.star_rounded,
                                  color: AppColors.accent,
                                  size: 16,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  widget.rating == 0
                                      ? 'Henüz puanlanmadı'
                                      : '${widget.rating.toStringAsFixed(1)} / 5.0',
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    fontFeatures: [
                                      ui.FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'GÜNLÜK NOTU',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.9,
                        ),
                      ),
                    ),
                    Text(
                      '$_characterCount / 500',
                      style: const TextStyle(
                        color: AppColors.textDisabled,
                        fontSize: 11,
                        fontFeatures: [ui.FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _controller,
                  autofocus: true,
                  minLines: 4,
                  maxLines: 8,
                  maxLength: 500,
                  onChanged: (value) =>
                      setState(() => _characterCount = value.length),
                  textCapitalization: TextCapitalization.sentences,
                  keyboardType: TextInputType.multiline,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Bu seri hakkında aklında kalanları yaz...',
                    alignLabelWithHint: true,
                    counterText: '',
                    filled: true,
                    fillColor: AppColors.cardBackground,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.divider),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.divider),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.accent),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('İptal'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: AppColors.background,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: () =>
                            Navigator.of(context).pop(_controller.text),
                        icon: const Icon(Icons.bookmark_add_rounded),
                        label: const Text('İncelemeyi Kaydet'),
                      ),
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

class _SeriesHero extends StatelessWidget {
  const _SeriesHero({required this.media});

  final AniListMedia media;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 316,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (media.bannerUrl != null && media.bannerUrl!.isNotEmpty)
            ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Image.network(
                media.bannerUrl!,
                fit: BoxFit.cover,
                cacheWidth: 1200,
                filterQuality: FilterQuality.low,
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : const ShimmerLoading(
                        child: ColoredBox(color: AppColors.shimmerBase),
                      ),
                errorBuilder: (context, error, stackTrace) =>
                    const _SeriesBackdrop(),
              ),
            )
          else
            const _SeriesBackdrop(),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x44303030),
                  Color(0xAA121212),
                  AppColors.background,
                ],
                stops: [0, 0.52, 1],
              ),
            ),
          ),
          Positioned(
            left: 16,
            top: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.background.withValues(alpha: 0.62),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.auto_awesome_rounded,
                    size: 14,
                    color: AppColors.accent,
                  ),
                  SizedBox(width: 6),
                  Text(
                    'ANILIST  ·  MANGA',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 20,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _SeriesPoster(url: media.coverUrl),
                const SizedBox(width: 16),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          media.title,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontSize: 21, height: 1.15),
                        ),
                        const SizedBox(height: 10),
                        _StatusPill(status: media.status),
                        const SizedBox(height: 9),
                        Text(
                          media.totalChapters == null
                              ? 'Bölüm sayısı bilinmiyor'
                              : '${media.totalChapters} bölüm',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                        if (media.averageScore != null) ...[
                          const SizedBox(height: 5),
                          Row(
                            children: [
                              const Icon(
                                Icons.star_rounded,
                                color: AppColors.accent,
                                size: 17,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${(media.averageScore! / 10).toStringAsFixed(1)} / 10',
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
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

class _SeriesPoster extends StatelessWidget {
  const _SeriesPoster({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      height: 172,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: url.isEmpty
          ? const _ImagePlaceholder()
          : Image.network(
              url,
              fit: BoxFit.cover,
              cacheWidth: 480,
              filterQuality: FilterQuality.low,
              loadingBuilder: (context, child, progress) => progress == null
                  ? child
                  : const ShimmerLoading(
                      child: ColoredBox(color: AppColors.shimmerBase),
                    ),
              errorBuilder: (context, error, stackTrace) =>
                  const _ImagePlaceholder(),
            ),
    );
  }
}

class _QuickActionsCard extends StatelessWidget {
  const _QuickActionsCard({
    required this.media,
    required this.tracked,
    required this.onStatusChanged,
    required this.onRatingChanged,
    required this.onChapterChanged,
    required this.chapterProgressPreview,
    required this.onChapterProgressChanged,
    required this.onChapterProgressEnd,
    required this.onEditChapterCount,
    required this.onEditReview,
  });

  final AniListMedia media;
  final TrackedSeries? tracked;
  final ValueChanged<TrackedSeriesStatus> onStatusChanged;
  final ValueChanged<double> onRatingChanged;
  final ValueChanged<int> onChapterChanged;
  final double? chapterProgressPreview;
  final ValueChanged<double> onChapterProgressChanged;
  final ValueChanged<double> onChapterProgressEnd;
  final VoidCallback onEditChapterCount;
  final VoidCallback onEditReview;

  @override
  Widget build(BuildContext context) {
    final status = tracked?.status ?? TrackedSeriesStatus.planToRead;
    final rating = tracked?.rating ?? 0.0;
    final chaptersRead = tracked?.chaptersRead ?? 0;
    final totalChapters = tracked?.totalChapters ?? media.totalChapters;
    final displayedChaptersRead =
        chapterProgressPreview?.round() ?? chaptersRead;
    final hasReview = tracked?.reviewNote?.isNotEmpty ?? false;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.12)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'DURUM',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              DropdownButton<TrackedSeriesStatus>(
                value: status,
                underline: const SizedBox.shrink(),
                dropdownColor: AppColors.surface,
                iconEnabledColor: AppColors.accent,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                ),
                items: TrackedSeriesStatus.values
                    .map(
                      (item) => DropdownMenuItem(
                        value: item,
                        child: Text(item.displayName),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value != null) onStatusChanged(value);
                },
              ),
            ],
          ),
          if (tracked == null) ...[
            const SizedBox(height: 2),
            const Text(
              'Durum, puan veya bölüm seçtiğinde takip listene eklenir.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ],
          const Divider(height: 24),
          _HalfStarRating(rating: rating, onChanged: onRatingChanged),
          const Divider(height: 24),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'BÖLÜM İLERLEMESİ',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Bir bölüm azalt',
                onPressed: displayedChaptersRead > 0
                    ? () => onChapterChanged(-1)
                    : null,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.remove_circle_outline_rounded),
              ),
              InkWell(
                onTap: onEditChapterCount,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$displayedChaptersRead / ${totalChapters ?? '?'}',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(width: 3),
                      const Icon(
                        Icons.edit_rounded,
                        size: 13,
                        color: AppColors.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Bir bölüm artır',
                onPressed:
                    totalChapters != null &&
                        displayedChaptersRead >= totalChapters
                    ? null
                    : () => onChapterChanged(1),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.add_circle_outline_rounded),
              ),
            ],
          ),
          if (totalChapters != null && totalChapters > 0)
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: AppColors.accent,
                inactiveTrackColor: AppColors.divider,
                thumbColor: AppColors.accent,
                overlayColor: AppColors.accent.withValues(alpha: 0.16),
                trackHeight: 4,
                showValueIndicator: ShowValueIndicator.onlyForContinuous,
                valueIndicatorColor: AppColors.surface,
                valueIndicatorTextStyle: const TextStyle(
                  color: AppColors.accent,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
              child: Slider(
                min: 0,
                max: totalChapters.toDouble(),
                divisions: totalChapters,
                value: (chapterProgressPreview ?? chaptersRead.toDouble())
                    .clamp(0.0, totalChapters.toDouble()),
                label: '$displayedChaptersRead / $totalChapters',
                onChanged: onChapterProgressChanged,
                onChangeEnd: onChapterProgressEnd,
              ),
            ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onEditReview,
              icon: Icon(
                hasReview
                    ? Icons.edit_note_rounded
                    : Icons.rate_review_outlined,
              ),
              label: Text(hasReview ? 'Notu düzenle' : 'İnceleme / Not ekle'),
            ),
          ),
        ],
      ),
    );
  }
}

class _HalfStarRating extends StatefulWidget {
  const _HalfStarRating({required this.rating, required this.onChanged});

  final double rating;
  final ValueChanged<double> onChanged;

  @override
  State<_HalfStarRating> createState() => _HalfStarRatingState();
}

class _HalfStarRatingState extends State<_HalfStarRating> {
  double? _previewRating;

  double get _displayedRating => _previewRating ?? widget.rating;

  void _setRatingFromPosition(double dx, double width, {required bool commit}) {
    if (width <= 0) return;
    final safeDx = dx.clamp(0.0, width - 0.001);
    final starWidth = width / 5;
    final index = (safeDx / starWidth).floor().clamp(0, 4);
    final withinStar = safeDx - index * starWidth;
    final rating = index + (withinStar < starWidth / 2 ? 0.5 : 1.0);

    if (commit) {
      setState(() => _previewRating = null);
      widget.onChanged(rating.toDouble());
    } else {
      setState(() => _previewRating = rating.toDouble());
    }
  }

  void _commitPreview() {
    final rating = _previewRating;
    if (rating == null) return;
    setState(() => _previewRating = null);
    widget.onChanged(rating);
  }

  String _captionFor(double rating) {
    if (rating == 0) return 'Sürükle veya dokunarak puanla';
    if (rating < 1.5) return 'Zayıf';
    if (rating < 2.5) return 'Ortalama';
    if (rating < 3.5) return 'İyi';
    if (rating < 4.5) return 'Çok iyi';
    if (rating < 5) return 'Başyapıt';
    return 'Kusursuz';
  }

  @override
  Widget build(BuildContext context) {
    final rating = _displayedRating;
    final score = rating == 0 ? '—' : rating.toStringAsFixed(1);

    return Semantics(
      slider: true,
      label: 'Kişisel seri puanı',
      value: '$score / 5.0',
      increasedValue:
          '${(widget.rating + 0.5).clamp(0.0, 5.0).toStringAsFixed(1)} / 5.0',
      decreasedValue:
          '${(widget.rating - 0.5).clamp(0.0, 5.0).toStringAsFixed(1)} / 5.0',
      onIncrease: () =>
          widget.onChanged((widget.rating + 0.5).clamp(0, 5).toDouble()),
      onDecrease: () =>
          widget.onChanged((widget.rating - 0.5).clamp(0, 5).toDouble()),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'PUANIM',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                child: Row(
                  key: ValueKey(score),
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      score,
                      style: const TextStyle(
                        color: AppColors.accent,
                        fontSize: 25,
                        fontWeight: FontWeight.w800,
                        height: 1,
                        fontFeatures: [ui.FontFeature.tabularFigures()],
                      ),
                    ),
                    const Text(
                      ' / 5.0',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          LayoutBuilder(
            builder: (context, constraints) {
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) => _setRatingFromPosition(
                  details.localPosition.dx,
                  constraints.maxWidth,
                  commit: true,
                ),
                onHorizontalDragStart: (details) => _setRatingFromPosition(
                  details.localPosition.dx,
                  constraints.maxWidth,
                  commit: false,
                ),
                onHorizontalDragUpdate: (details) => _setRatingFromPosition(
                  details.localPosition.dx,
                  constraints.maxWidth,
                  commit: false,
                ),
                onHorizontalDragEnd: (_) => _commitPreview(),
                child: SizedBox(
                  height: 52,
                  child: Row(
                    children: [
                      for (var index = 0; index < 5; index++)
                        Expanded(
                          child: Center(
                            child: AnimatedScale(
                              scale: rating > index ? 1.08 : 1,
                              duration: const Duration(milliseconds: 120),
                              child: _StarIcon(
                                fill: (rating - index).clamp(0.0, 1.0),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
          Row(
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 140),
                child: Text(
                  _captionFor(rating),
                  key: ValueKey(_captionFor(rating)),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              const Text(
                'Yarım yıldız adımları',
                style: TextStyle(color: AppColors.textDisabled, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StarIcon extends StatelessWidget {
  const _StarIcon({required this.fill});

  final double fill;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        if (fill > 0)
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.accent.withValues(alpha: 0.08),
              boxShadow: [
                BoxShadow(
                  color: AppColors.accent.withValues(alpha: 0.34 * fill),
                  blurRadius: 15,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        const Icon(
          Icons.star_border_rounded,
          color: AppColors.accent,
          size: 31,
        ),
        if (fill > 0)
          ClipRect(
            child: Align(
              alignment: Alignment.centerLeft,
              widthFactor: fill,
              child: const Icon(
                Icons.star_rounded,
                color: AppColors.accent,
                size: 31,
              ),
            ),
          ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final String? status;

  @override
  Widget build(BuildContext context) {
    final (label, icon) = switch (status) {
      'RELEASING' => ('Devam Ediyor', Icons.autorenew_rounded),
      'FINISHED' => ('Tamamlandı', Icons.check_circle_outline_rounded),
      'NOT_YET_RELEASED' => ('Yakında', Icons.schedule_rounded),
      'HIATUS' => ('Ara Verildi', Icons.pause_circle_outline_rounded),
      'CANCELLED' => ('İptal Edildi', Icons.block_rounded),
      _ => ('Durum Bilinmiyor', Icons.info_outline_rounded),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.accent),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.accent,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewNoteCard extends StatelessWidget {
  const _ReviewNoteCard({required this.note});

  final String note;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.rate_review_outlined,
                  color: AppColors.accent,
                  size: 18,
                ),
                SizedBox(width: 8),
                Text(
                  'Günlüğüm',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              note,
              style: const TextStyle(
                color: AppColors.textSecondary,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SeriesBackdrop extends StatelessWidget {
  const _SeriesBackdrop();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.topRight,
          radius: 1.35,
          colors: [Color(0xFF33454B), AppColors.cardBackground],
        ),
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.5),
          colors: [Color(0xFF2A3B40), AppColors.cardBackground],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.auto_stories_rounded,
          color: AppColors.textDisabled,
          size: 34,
        ),
      ),
    );
  }
}
