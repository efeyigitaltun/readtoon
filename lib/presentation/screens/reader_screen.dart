import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:volume_controller/volume_controller.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../data/decoders/comic_decoder_factory.dart';
import '../../data/decoders/i_comic_decoder.dart';
import '../../data/models/comic_book.dart';
import '../providers/reader_provider.dart';
import '../providers/settings_provider.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Reader Screen
// ═══════════════════════════════════════════════════════════════════════════════

class ReaderScreen extends ConsumerStatefulWidget {
  final ComicBook comic;
  const ReaderScreen({super.key, required this.comic});

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  // ─── Decoder – tüm sayfa yüklemelerini yönetir ────────────────────────────
  late IComicDecoder _decoder;

  late PageController _pageController;
  final ScrollController _scrollController = ScrollController();

  int _pageCount = 0;
  bool _isLoading = true;
  String? _loadError;
  double _lastVolume = -1;

  // ─── Yaşam Döngüsü ──────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _setupVolumeListener();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final mode = ref.read(readingModeProvider);
      ref.read(currentPageProvider.notifier).initialize(widget.comic, mode);
      await _initDecoder();
    });
  }

  @override
  void dispose() {
    VolumeController().removeListener();
    _decoder.dispose();
    _pageController.dispose();
    _scrollController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ─── Decoder ve Sayfa Sayısı Yükleme ────────────────────────────────────────

  Future<void> _initDecoder() async {
    try {
      // Factory: uzantıya göre doğru decoder'ı oluşturur (ZIP/RAR/PDF)
      _decoder = ComicDecoderFactory.createForFile(widget.comic.filePath);
      final count = await _decoder.getPageCount();
      if (mounted) {
        setState(() {
          _pageCount = count;
          _isLoading = false;
        });
        _initPageController();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = 'Dosya açılamadı: ${e.runtimeType}';
          _isLoading = false;
        });
      }
    }
  }

  void _initPageController() {
    final startPage = ref.read(currentPageProvider);
    _pageController = PageController(
      initialPage: startPage.clamp(0, (_pageCount - 1).clamp(0, 99999)),
    );
  }

  // ─── Ses Tuşu → Sayfa Atlama ─────────────────────────────────────────────

  void _setupVolumeListener() {
    VolumeController().showSystemUI = false;
    VolumeController()
        .getVolume()
        .then((v) => _lastVolume = v)
        .catchError((_) => _lastVolume = 0.5);

    VolumeController().listener((volume) {
      if (_lastVolume < 0 || !mounted) {
        _lastVolume = volume;
        return;
      }
      final delta = volume - _lastVolume;
      _lastVolume = volume;
      if (delta.abs() < 0.01) return;

      final pageNotifier = ref.read(currentPageProvider.notifier);
      final isWebtoon =
          ref.read(readingModeProvider) == AppConstants.readingModeWebtoon;
      final screenH = MediaQuery.of(context).size.height;

      if (delta < 0) {
        if (isWebtoon) {
          _scrollController.animateTo(
            _scrollController.offset + screenH * 0.9,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        } else {
          pageNotifier.nextPage();
          _safePageNext();
        }
      } else {
        if (isWebtoon) {
          _scrollController.animateTo(
            _scrollController.offset - screenH * 0.9,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        } else {
          pageNotifier.prevPage();
          _safePagePrev();
        }
      }
    });
  }

  void _safePageNext() {
    if (_pageController.hasClients) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    }
  }

  void _safePagePrev() {
    if (_pageController.hasClients) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    }
  }

  // ─── Dokunma Alanı Yönetimi ─────────────────────────────────────────────────

  void _handleTap(TapUpDetails details) {
    final width = MediaQuery.of(context).size.width;
    final screenH = MediaQuery.of(context).size.height;
    final x = details.globalPosition.dx;
    final isWebtoon =
        ref.read(readingModeProvider) == AppConstants.readingModeWebtoon;
    final pageNotifier = ref.read(currentPageProvider.notifier);

    if (x < width * AppConstants.tapZonePrevRatio) {
      if (isWebtoon) {
        _scrollController.animateTo(
          _scrollController.offset - screenH * 0.9,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      } else {
        pageNotifier.prevPage();
        _safePagePrev();
      }
    } else if (x > width * (1 - AppConstants.tapZoneNextRatio)) {
      if (isWebtoon) {
        _scrollController.animateTo(
          _scrollController.offset + screenH * 0.9,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      } else {
        pageNotifier.nextPage();
        _safePageNext();
      }
    } else {
      ref.read(readerMenuVisibleProvider.notifier).toggle();
      _updateSystemUI();
    }
  }

  void _updateSystemUI() {
    final menuVisible = ref.read(readerMenuVisibleProvider);
    if (menuVisible) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isMenuVisible = ref.watch(readerMenuVisibleProvider);
    final currentPage = ref.watch(currentPageProvider);
    final isWebtoon =
        ref.watch(readingModeProvider) == AppConstants.readingModeWebtoon;

    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.accent),
        ),
      );
    }

    if (_loadError != null || _pageCount == 0) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: Text(widget.comic.title),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _loadError ?? 'Bu dosyada okunabilir sayfa bulunamadı.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: _handleTap,
        child: Stack(
          children: [
            // ─── Okuma İçeriği ───────────────────────────────────────────
            if (isWebtoon)
              _WebtoonView(
                decoder: _decoder,
                pageCount: _pageCount,
                scrollController: _scrollController,
              )
            else
              _MangaView(
                decoder: _decoder,
                pageCount: _pageCount,
                pageController: _pageController,
                onPageChanged: (index) {
                  ref.read(currentPageProvider.notifier).goToPage(index);
                },
              ),

            // ─── Üst Menü ────────────────────────────────────────────────
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              top: isMenuVisible ? 0 : -(kToolbarHeight + 56),
              left: 0,
              right: 0,
              child: _TopMenu(comic: widget.comic),
            ),

            // ─── Alt Menü ────────────────────────────────────────────────
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              bottom: isMenuVisible ? 0 : -120,
              left: 0,
              right: 0,
              child: _BottomMenu(
                currentPage: currentPage,
                totalPages: _pageCount,
                onSliderChanged: (value) {
                  final index = (value * (_pageCount - 1)).round();
                  ref.read(currentPageProvider.notifier).goToPage(index);
                  if (!isWebtoon && _pageController.hasClients) {
                    _pageController.jumpToPage(index);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Webtoon Modu – Dikey ListView (Lazy Loading)
// ═══════════════════════════════════════════════════════════════════════════════

class _WebtoonView extends StatelessWidget {
  final IComicDecoder decoder;
  final int pageCount;
  final ScrollController scrollController;

  const _WebtoonView({
    required this.decoder,
    required this.pageCount,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: scrollController,
      itemCount: pageCount,
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      itemBuilder: (context, index) => _LazyPageImage(
        decoder: decoder,
        pageIndex: index,
        fit: BoxFit.fitWidth,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Manga Modu – Yatay PageView (Sağdan Sola)
// ═══════════════════════════════════════════════════════════════════════════════

class _MangaView extends StatelessWidget {
  final IComicDecoder decoder;
  final int pageCount;
  final PageController pageController;
  final ValueChanged<int> onPageChanged;

  const _MangaView({
    required this.decoder,
    required this.pageCount,
    required this.pageController,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: pageController,
      reverse: true, // Sağdan sola (manga yönü)
      onPageChanged: onPageChanged,
      itemCount: pageCount,
      itemBuilder: (context, index) => _LazyPageImage(
        decoder: decoder,
        pageIndex: index,
        fit: BoxFit.contain,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Lazy Page Image
// Decoder'ı doğrudan kullanır – format agnostik, RAM dostu.
// ═══════════════════════════════════════════════════════════════════════════════

/// Tek bir sayfayı decoder üzerinden yükler.
/// Widget ağaçtan ayrıldığında sayfa verisi çöp toplayıcıya bırakılır.
class _LazyPageImage extends StatefulWidget {
  final IComicDecoder decoder;
  final int pageIndex;
  final BoxFit fit;

  const _LazyPageImage({
    required this.decoder,
    required this.pageIndex,
    required this.fit,
  });

  @override
  State<_LazyPageImage> createState() => _LazyPageImageState();
}

class _LazyPageImageState extends State<_LazyPageImage> {
  Uint8List? _bytes;
  bool _loading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadPage();
  }

  Future<void> _loadPage() async {
    try {
      // Decoder: format ne olursa olsun doğru çözücüyü kullanır
      final bytes = await widget.decoder.getPage(widget.pageIndex);
      if (mounted) {
        setState(() {
          _bytes = bytes;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 300,
        child: Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.accent,
            ),
          ),
        ),
      );
    }

    if (_hasError || _bytes == null) {
      return SizedBox(
        height: 200,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.broken_image_rounded,
                  color: AppColors.textDisabled, size: 36),
              const SizedBox(height: 8),
              Text(
                'Sayfa ${widget.pageIndex + 1} yüklenemedi',
                style: const TextStyle(
                    color: AppColors.textDisabled, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    return Image.memory(
      _bytes!,
      fit: widget.fit,
      width: double.infinity,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => const SizedBox(
        height: 200,
        child:
            Center(child: Icon(Icons.broken_image_rounded, size: 36, color: AppColors.textDisabled)),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Üst Menü
// ═══════════════════════════════════════════════════════════════════════════════

class _TopMenu extends ConsumerWidget {
  final ComicBook comic;
  const _TopMenu({required this.comic});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isWebtoon =
        ref.watch(readingModeProvider) == AppConstants.readingModeWebtoon;

    return Container(
      color: AppColors.readerMenuBackground,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: kToolbarHeight,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded,
                    color: AppColors.textPrimary),
                onPressed: () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: Text(
                  comic.title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: isWebtoon ? 'Manga moduna geç' : 'Webtoon moduna geç',
                icon: Icon(
                  isWebtoon
                      ? Icons.swap_vert_rounded
                      : Icons.swap_horiz_rounded,
                  color: AppColors.accent,
                ),
                onPressed: () {
                  final newMode = isWebtoon
                      ? AppConstants.readingModeManga
                      : AppConstants.readingModeWebtoon;
                  ref.read(readingModeProvider.notifier).setMode(newMode);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Alt Menü
// ═══════════════════════════════════════════════════════════════════════════════

class _BottomMenu extends StatelessWidget {
  final int currentPage;
  final int totalPages;
  final ValueChanged<double> onSliderChanged;

  const _BottomMenu({
    required this.currentPage,
    required this.totalPages,
    required this.onSliderChanged,
  });

  @override
  Widget build(BuildContext context) {
    final progress = totalPages > 1 ? currentPage / (totalPages - 1) : 0.0;

    return Container(
      color: AppColors.readerMenuBackground,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: AppColors.accent,
                  inactiveTrackColor: AppColors.divider,
                  thumbColor: AppColors.accent,
                  overlayColor: AppColors.accent.withValues(alpha: 0.2),
                  trackHeight: 3,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 8),
                ),
                child: Slider(
                  value: progress.clamp(0.0, 1.0),
                  onChanged: onSliderChanged,
                ),
              ),
              Text(
                '${currentPage + 1} / $totalPages',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }
}
