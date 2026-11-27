import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../data/decoders/comic_decoder_factory.dart';
import '../../data/decoders/i_comic_decoder.dart';
import '../../data/models/comic_book.dart';
import '../../data/services/saf_file_access_service.dart';
import '../providers/library_provider.dart';
import '../providers/reader_provider.dart';
import '../providers/settings_provider.dart';
import 'settings_screen.dart';

const _doubleTapInterval = Duration(milliseconds: 300);

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
  static const double _sideControlsWidth = 60;
  static const double _sideControlsHeight = 120;

  IComicDecoder? _decoder;
  PageController? _pageController;
  final ScrollController _scrollController = ScrollController();
  Offset? _sideControlsPosition;
  final GlobalKey<_WebtoonViewState> _webtoonViewKey =
      GlobalKey<_WebtoonViewState>();
  Timer? _tapTimer;
  DateTime? _lastTapAt;
  TapUpDetails? _pendingTap;

  int _pageCount = 0;
  int? _sliderPreviewPage;
  bool _isLoading = true;
  String? _loadError;

  // ─── Yaşam Döngüsü ──────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      _applyWakelock();
      final settings = ref.read(appSettingsProvider);
      final mode = settings.isWebtoonMode
          ? AppConstants.readingModeWebtoon
          : AppConstants.readingModeManga;
      ref.read(currentPageProvider.notifier).initialize(widget.comic, mode);
      await _initDecoder();
    });
  }

  @override
  void dispose() {
    _tapTimer?.cancel();
    WakelockPlus.disable(); // Okuyucudan çıkınca her zaman kapat
    _decoder?.dispose();
    _pageController?.dispose();
    _scrollController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _applyWakelock() {
    final keepOn = ref.read(appSettingsProvider).keepScreenOn;
    WakelockPlus.toggle(enable: keepOn);
  }

  // ─── Decoder Yükleme ────────────────────────────────────────────────────────

  Future<void> _initDecoder() async {
    try {
      final localPath = await SafFileAccessService().ensureLocalFile(
        widget.comic.filePath,
        displayName: widget.comic.sourceFileName,
      );
      final decoder = ComicDecoderFactory.createForFile(localPath);
      _decoder = decoder;
      final count = await decoder.getPageCount();
      if (mounted) {
        setState(() {
          _pageCount = count;
          _isLoading = false;
        });
        _initPageController();
      } else {
        await decoder.dispose();
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
      initialPage: startPage.clamp(0, (_pageCount - 1).clamp(0, 999999)),
    );
    setState(() {}); // controller hazır, yeniden çiz
  }

  // ─── Dokunma Alanı ──────────────────────────────────────────────────────────

  void _handleTap(TapUpDetails details) {
    if (!ref.read(appSettingsProvider).doubleTapZoom) {
      _performTap(details);
      return;
    }

    final now = DateTime.now();
    final previousTap = _lastTapAt;
    if (previousTap != null &&
        now.difference(previousTap) <= _doubleTapInterval) {
      // Çift dokunuşu okuma alanına yayma; sayfa değiştirme/menü açma iptal.
      _tapTimer?.cancel();
      _tapTimer = null;
      _pendingTap = null;
      _lastTapAt = null;
      return;
    }

    _lastTapAt = now;
    _pendingTap = details;
    _tapTimer?.cancel();
    _tapTimer = Timer(_doubleTapInterval, () {
      final pendingTap = _pendingTap;
      _pendingTap = null;
      _lastTapAt = null;
      if (mounted && pendingTap != null) _performTap(pendingTap);
    });
  }

  Offset _defaultSideControlsPosition() {
    final screenSize = MediaQuery.sizeOf(context);
    final safePadding = MediaQuery.paddingOf(context);
    return _boundedSideControlsPosition(
      Offset(
        screenSize.width - safePadding.right - _sideControlsWidth - 12,
        (screenSize.height - _sideControlsHeight) / 2,
      ),
    );
  }

  Offset _boundedSideControlsPosition(Offset position) {
    final screenSize = MediaQuery.sizeOf(context);
    final safePadding = MediaQuery.paddingOf(context);
    final minX = safePadding.left + 8;
    final maxX = math.max(
      minX,
      screenSize.width - safePadding.right - _sideControlsWidth - 8,
    );
    final minY = safePadding.top + 8;
    final maxY = math.max(
      minY,
      screenSize.height - safePadding.bottom - _sideControlsHeight - 8,
    );
    return Offset(
      position.dx.clamp(minX, maxX).toDouble(),
      position.dy.clamp(minY, maxY).toDouble(),
    );
  }

  void _moveSideControls(DragUpdateDetails details) {
    final current = _boundedSideControlsPosition(
      _sideControlsPosition ?? _defaultSideControlsPosition(),
    );
    setState(() {
      _sideControlsPosition = _boundedSideControlsPosition(
        current + details.delta,
      );
    });
  }

  void _performTap(TapUpDetails details) {
    final screenSize = MediaQuery.sizeOf(context);
    final width = screenSize.width;
    final screenH = screenSize.height;
    final x = details.globalPosition.dx;
    final y = details.globalPosition.dy;

    // Overlay kontrollerine (özellikle Slider'a) dokunmayı tap zone olarak
    // yorumlama; sürüklenebilir grup bırakıldığı yerde de korunur.
    final menuVisible = ref.read(readerMenuVisibleProvider);
    final controlsPosition = _boundedSideControlsPosition(
      _sideControlsPosition ?? _defaultSideControlsPosition(),
    );
    final tappedSideControls = Rect.fromLTWH(
      controlsPosition.dx,
      controlsPosition.dy,
      _sideControlsWidth,
      _sideControlsHeight,
    ).contains(details.globalPosition);
    if (menuVisible && (y < 112 || y > screenH - 160 || tappedSideControls)) {
      return;
    }

    final isWebtoon = ref.read(appSettingsProvider).isWebtoonMode;
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

  void _commitSliderPage(double value, {required bool isWebtoon}) {
    final index = (value * (_pageCount - 1)).round().clamp(0, _pageCount - 1);
    if (mounted) setState(() => _sliderPreviewPage = null);
    ref.read(currentPageProvider.notifier).goToPage(index);
    if (isWebtoon) {
      _webtoonViewKey.currentState?.jumpToPage(index);
    } else if (_pageController?.hasClients ?? false) {
      _pageController!.jumpToPage(index);
    }
  }

  void _updateSystemUI() {
    final menuVisible = ref.read(readerMenuVisibleProvider);
    SystemChrome.setEnabledSystemUIMode(
      menuVisible ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky,
    );
  }

  Future<void> _openSettings() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (!mounted) return;

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
    );
    if (!mounted) return;

    final menuVisible = ref.read(readerMenuVisibleProvider);
    await SystemChrome.setEnabledSystemUIMode(
      menuVisible ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky,
    );
  }

  void _safePageNext() {
    if (_pageController?.hasClients ?? false) {
      _pageController!.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    }
  }

  void _safePagePrev() {
    if (_pageController?.hasClients ?? false) {
      _pageController!.previousPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    }
  }

  void _openAdjacentChapter(List<ComicBook> comics, int step) {
    final currentIndex = comics.indexWhere(
      (comic) => comic.id == widget.comic.id,
    );
    final nextIndex = currentIndex + step;
    if (currentIndex < 0 || nextIndex < 0 || nextIndex >= comics.length) return;

    Navigator.of(context).pushReplacement<void, void>(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (context, animation, secondaryAnimation) =>
            ReaderScreen(comic: comics[nextIndex]),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(
      appSettingsProvider.select((settings) => settings.isWebtoonMode),
      (previousMode, isWebtoonMode) {
        if (previousMode == true && !isWebtoonMode) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final page = ref.read(currentPageProvider);
            if ((_pageController?.hasClients ?? false) && _pageCount > 0) {
              _pageController!.jumpToPage(page.clamp(0, _pageCount - 1));
            }
          });
        }
      },
    );

    final isMenuVisible = ref.watch(readerMenuVisibleProvider);
    final currentPage = ref.watch(currentPageProvider);
    final displayedPage = _sliderPreviewPage ?? currentPage;
    final settings = ref.watch(appSettingsProvider);
    final libraryComics =
        ref.watch(libraryProvider).valueOrNull ?? const <ComicBook>[];
    final currentComicIndex = libraryComics.indexWhere(
      (comic) => comic.id == widget.comic.id,
    );
    final screenWidth = MediaQuery.sizeOf(context).width;
    final sideControlsPosition = _boundedSideControlsPosition(
      _sideControlsPosition ?? _defaultSideControlsPosition(),
    );

    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: AppColors.accent)),
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
            if (settings.isWebtoonMode)
              _WebtoonView(
                key: _webtoonViewKey,
                decoder: _decoder!,
                pageCount: _pageCount,
                initialPage: currentPage,
                doubleTapZoom: settings.doubleTapZoom,
                scrollController: _scrollController,
                onPageChanged: (index) {
                  ref.read(currentPageProvider.notifier).goToPage(index);
                },
              )
            else
              _MangaView(
                decoder: _decoder!,
                pageCount: _pageCount,
                pageController: _pageController!,
                isRTL: settings.isRTL,
                doubleTapZoom: settings.doubleTapZoom,
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
              bottom: isMenuVisible ? 0 : -168,
              left: 0,
              right: 0,
              child: _BottomMenu(
                currentPage: displayedPage,
                totalPages: _pageCount,
                hasPreviousChapter: currentComicIndex > 0,
                hasNextChapter:
                    currentComicIndex >= 0 &&
                    currentComicIndex < libraryComics.length - 1,
                onChapterStep: (step) =>
                    _openAdjacentChapter(libraryComics, step),
                onSliderChanged: (value) {
                  setState(() {
                    _sliderPreviewPage = (value * (_pageCount - 1))
                        .round()
                        .clamp(0, _pageCount - 1);
                  });
                },
                onSliderChangeEnd: (value) =>
                    _commitSliderPage(value, isWebtoon: settings.isWebtoonMode),
              ),
            ),

            // ─── Sağ Kenar Araçları ───────────────────────────────────────
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              left: isMenuVisible ? sideControlsPosition.dx : screenWidth + 8,
              top: sideControlsPosition.dy,
              width: _sideControlsWidth,
              height: _sideControlsHeight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: _moveSideControls,
                child: _ReaderSideControls(
                  isRTL: settings.isRTL,
                  onToggleDirection: () => ref
                      .read(appSettingsProvider.notifier)
                      .setRTL(!settings.isRTL),
                  onOpenSettings: _openSettings,
                ),
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

class _WebtoonView extends StatefulWidget {
  final IComicDecoder decoder;
  final int pageCount;
  final int initialPage;
  final bool doubleTapZoom;
  final ScrollController scrollController;
  final ValueChanged<int> onPageChanged;

  const _WebtoonView({
    super.key,
    required this.decoder,
    required this.pageCount,
    required this.initialPage,
    required this.doubleTapZoom,
    required this.scrollController,
    required this.onPageChanged,
  });

  @override
  State<_WebtoonView> createState() => _WebtoonViewState();
}

class _WebtoonViewState extends State<_WebtoonView> {
  final GlobalKey _viewportKey = GlobalKey();
  final Map<int, GlobalKey> _visiblePageKeys = {};
  int? _lastReportedPage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.initialPage > 0) jumpToPage(widget.initialPage);
      _updateVisiblePage();
    });
  }

  /// Slider/okuma geçmişi hedefini ListView'a taşır.
  /// Sayfa yükseklikleri değişken olduğundan önce toplam scroll oranına atlar,
  /// hedef öğe oluşturulduğunda onu görünür alanın ortasına hizalar.
  void jumpToPage(int index) {
    if (!mounted ||
        !widget.scrollController.hasClients ||
        widget.pageCount <= 0) {
      return;
    }

    final targetIndex = index.clamp(0, widget.pageCount - 1);
    final targetKey = _visiblePageKeys[targetIndex];
    final targetBox = targetKey?.currentContext?.findRenderObject();
    final viewportBox = _viewportKey.currentContext?.findRenderObject();

    if (targetBox is RenderBox &&
        targetBox.hasSize &&
        viewportBox is RenderBox &&
        viewportBox.hasSize) {
      _alignPage(targetBox, viewportBox);
      return;
    }

    final position = widget.scrollController.position;
    final fraction = widget.pageCount <= 1
        ? 0.0
        : targetIndex / (widget.pageCount - 1);
    final offset = (position.maxScrollExtent * fraction).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    widget.scrollController.jumpTo(offset);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final pageRenderBox = _visiblePageKeys[targetIndex]?.currentContext
          ?.findRenderObject();
      final viewportRenderBox = _viewportKey.currentContext?.findRenderObject();
      if (pageRenderBox is RenderBox &&
          pageRenderBox.hasSize &&
          viewportRenderBox is RenderBox &&
          viewportRenderBox.hasSize) {
        _alignPage(pageRenderBox, viewportRenderBox);
      }
      _updateVisiblePage();
    });
  }

  void _alignPage(RenderBox pageBox, RenderBox viewportBox) {
    final pageCenter =
        pageBox.localToGlobal(Offset.zero).dy + pageBox.size.height / 2;
    final viewportTop = viewportBox.localToGlobal(Offset.zero).dy;
    final viewportCenter = viewportTop + viewportBox.size.height / 2;
    final position = widget.scrollController.position;
    final targetOffset = (position.pixels + pageCenter - viewportCenter).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    widget.scrollController.jumpTo(targetOffset);
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification ||
        notification is ScrollEndNotification ||
        notification is ScrollMetricsNotification) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _updateVisiblePage();
      });
    }
    return false;
  }

  void _updateVisiblePage() {
    final viewportRenderObject = _viewportKey.currentContext
        ?.findRenderObject();
    if (viewportRenderObject is! RenderBox || !viewportRenderObject.hasSize) {
      return;
    }

    final viewportTop = viewportRenderObject.localToGlobal(Offset.zero).dy;
    final viewportHeight = viewportRenderObject.size.height;
    final viewportBottom = viewportTop + viewportHeight;
    final viewportCenter = viewportTop + viewportHeight / 2;

    int? bestIndex;
    double bestVisibleHeight = -1;
    bool centerIsInsideBest = false;

    for (final entry in _visiblePageKeys.entries) {
      final renderObject = entry.value.currentContext?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) continue;

      final pageTop = renderObject.localToGlobal(Offset.zero).dy;
      final pageBottom = pageTop + renderObject.size.height;
      final visibleHeight = math.max(
        0.0,
        math.min(pageBottom, viewportBottom) - math.max(pageTop, viewportTop),
      );
      final centerIsInside =
          viewportCenter >= pageTop && viewportCenter < pageBottom;

      if ((centerIsInside && !centerIsInsideBest) ||
          (centerIsInside == centerIsInsideBest &&
              visibleHeight > bestVisibleHeight)) {
        bestIndex = entry.key;
        bestVisibleHeight = visibleHeight;
        centerIsInsideBest = centerIsInside;
      }
    }

    if (bestIndex != null && bestIndex != _lastReportedPage) {
      _lastReportedPage = bestIndex;
      widget.onPageChanged(bestIndex);
    }
  }

  void _removePageKey(int index, GlobalKey key) {
    if (identical(_visiblePageKeys[index], key)) {
      _visiblePageKeys.remove(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      key: _viewportKey,
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScrollNotification,
        child: ListView.builder(
          controller: widget.scrollController,
          itemCount: widget.pageCount,
          // Uzak sayfaların widget/decode verileri bellekte tutulmaz.
          addAutomaticKeepAlives: false,
          addRepaintBoundaries: true,
          itemBuilder: (context, index) {
            final pageKey = _visiblePageKeys.putIfAbsent(index, GlobalKey.new);
            return _TrackedWebtoonPage(
              pageKey: pageKey,
              pageIndex: index,
              onDisposed: _removePageKey,
              child: _LazyPageImage(
                decoder: widget.decoder,
                pageIndex: index,
                fit: BoxFit.fitWidth,
                doubleTapZoom: widget.doubleTapZoom,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TrackedWebtoonPage extends StatefulWidget {
  final GlobalKey pageKey;
  final int pageIndex;
  final void Function(int index, GlobalKey key) onDisposed;
  final Widget child;

  const _TrackedWebtoonPage({
    required this.pageKey,
    required this.pageIndex,
    required this.onDisposed,
    required this.child,
  }) : super(key: pageKey);

  @override
  State<_TrackedWebtoonPage> createState() => _TrackedWebtoonPageState();
}

class _TrackedWebtoonPageState extends State<_TrackedWebtoonPage> {
  @override
  void dispose() {
    widget.onDisposed(widget.pageIndex, widget.pageKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// ═══════════════════════════════════════════════════════════════════════════════
// Manga Modu – Yatay PageView (RTL desteği)
// ═══════════════════════════════════════════════════════════════════════════════

class _MangaView extends StatelessWidget {
  final IComicDecoder decoder;
  final int pageCount;
  final PageController pageController;
  final bool isRTL;
  final bool doubleTapZoom;
  final ValueChanged<int> onPageChanged;

  const _MangaView({
    required this.decoder,
    required this.pageCount,
    required this.pageController,
    required this.isRTL,
    required this.doubleTapZoom,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: pageController,
      reverse: isRTL,
      onPageChanged: onPageChanged,
      itemCount: pageCount,
      itemBuilder: (context, index) => _LazyPageImage(
        decoder: decoder,
        pageIndex: index,
        fit: BoxFit.contain,
        doubleTapZoom: doubleTapZoom,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Lazy Page Image – yalnızca görünür/önbellek aralığındaki sayfayı yükler
// ═══════════════════════════════════════════════════════════════════════════════

class _LazyPageImage extends StatefulWidget {
  final IComicDecoder decoder;
  final int pageIndex;
  final BoxFit fit;
  final bool doubleTapZoom;

  const _LazyPageImage({
    required this.decoder,
    required this.pageIndex,
    required this.fit,
    required this.doubleTapZoom,
  });

  @override
  State<_LazyPageImage> createState() => _LazyPageImageState();
}

class _LazyPageImageState extends State<_LazyPageImage> {
  final TransformationController _transformationController =
      TransformationController();
  ui.Image? _pageImage;
  Offset? _doubleTapPosition;
  bool _loading = true;
  bool _hasError = false;
  bool _panEnabled = false;
  int _requestGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadPage();
  }

  @override
  void didUpdateWidget(covariant _LazyPageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageIndex != widget.pageIndex ||
        oldWidget.decoder != widget.decoder) {
      _requestGeneration++;
      _pageImage?.dispose();
      _pageImage = null;
      _loading = true;
      _hasError = false;
      _panEnabled = false;
      _transformationController.value = Matrix4.identity();
      _loadPage();
    }
  }

  @override
  void dispose() {
    _requestGeneration++;
    _pageImage?.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  Future<void> _loadPage() async {
    final generation = ++_requestGeneration;
    ui.Codec? codec;
    ui.Image? decodedImage;

    try {
      final bytes = await widget.decoder.getPage(widget.pageIndex);
      if (bytes == null) throw StateError('Sayfa verisi boş');

      final views = WidgetsBinding.instance.platformDispatcher.views;
      final requestedWidth = views.isEmpty
          ? 1080
          : math.min(views.first.physicalSize.width.round(), 1440);
      codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: math.max(1, requestedWidth),
      );
      final frame = await codec.getNextFrame();
      decodedImage = frame.image;

      if (mounted && generation == _requestGeneration) {
        setState(() {
          _pageImage = decodedImage;
          _loading = false;
          _hasError = false;
        });
        decodedImage = null; // Widget artık bu görüntünün sahibi.
      }
    } catch (_) {
      if (mounted && generation == _requestGeneration) {
        setState(() {
          _hasError = true;
          _loading = false;
        });
      }
    } finally {
      codec?.dispose();
      decodedImage?.dispose();
    }
  }

  void _toggleDoubleTapZoom() {
    if (!widget.doubleTapZoom) return;

    final currentScale = _transformationController.value.getMaxScaleOnAxis();
    if (currentScale > 1.01) {
      _transformationController.value = Matrix4.identity();
      setState(() => _panEnabled = false);
      return;
    }

    final focalPoint = _doubleTapPosition ?? Offset.zero;
    const scale = 2.2;
    _transformationController.value = Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
      ..setEntry(0, 3, focalPoint.dx * (1 - scale))
      ..setEntry(1, 3, focalPoint.dy * (1 - scale));
    setState(() => _panEnabled = true);
  }

  void _updatePanAvailability() {
    final shouldEnablePan =
        _transformationController.value.getMaxScaleOnAxis() > 1.01;
    if (shouldEnablePan != _panEnabled && mounted) {
      setState(() => _panEnabled = shouldEnablePan);
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

    final pageImage = _pageImage;
    if (_hasError || pageImage == null) {
      return SizedBox(
        height: 200,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.broken_image_rounded,
                color: AppColors.textDisabled,
                size: 36,
              ),
              const SizedBox(height: 8),
              Text(
                'Sayfa ${widget.pageIndex + 1} yüklenemedi',
                style: const TextStyle(
                  color: AppColors.textDisabled,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final isWebtoonPage = widget.fit == BoxFit.fitWidth;
        final height = isWebtoonPage
            ? width * pageImage.height / pageImage.width
            : constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : MediaQuery.sizeOf(context).height;

        // ListView'ın dikey ekseninde her satıra görüntü oranından sonlu bir
        // yükseklik verilir. Böylece InteractiveViewer hiçbir zaman unbounded
        // height ile ölçülmez.
        final boundedPage = SizedBox(
          width: width,
          height: height,
          child: InteractiveViewer(
            transformationController: _transformationController,
            constrained: true,
            panEnabled: _panEnabled,
            scaleEnabled: true,
            minScale: 1,
            maxScale: 3,
            boundaryMargin: EdgeInsets.zero,
            clipBehavior: Clip.hardEdge,
            onInteractionUpdate: (_) => _updatePanAvailability(),
            child: RawImage(
              image: pageImage,
              fit: widget.fit,
              width: width,
              height: height,
              filterQuality: FilterQuality.medium,
            ),
          ),
        );

        return GestureDetector(
          onDoubleTapDown: (details) =>
              _doubleTapPosition = details.localPosition,
          onDoubleTap: widget.doubleTapZoom ? _toggleDoubleTapZoom : null,
          child: boundedPage,
        );
      },
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
    final settings = ref.watch(appSettingsProvider);

    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.background.withValues(alpha: 0.85),
            border: Border(
              bottom: BorderSide(
                color: Colors.white.withValues(alpha: 0.08),
                width: 1,
              ),
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: kToolbarHeight,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: AppColors.textPrimary,
                    ),
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
                    tooltip: settings.isWebtoonMode
                        ? 'Manga moduna geç'
                        : 'Webtoon moduna geç',
                    icon: Icon(
                      settings.isWebtoonMode
                          ? Icons.swap_vert_rounded
                          : Icons.swap_horiz_rounded,
                      color: AppColors.accent,
                    ),
                    onPressed: () => ref
                        .read(appSettingsProvider.notifier)
                        .setWebtoonMode(!settings.isWebtoonMode),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Sağ Kenar Araçları
// ═══════════════════════════════════════════════════════════════════════════════

class _ReaderSideControls extends StatelessWidget {
  final bool isRTL;
  final VoidCallback onToggleDirection;
  final VoidCallback onOpenSettings;

  const _ReaderSideControls({
    required this.isRTL,
    required this.onToggleDirection,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
      decoration: BoxDecoration(
        color: AppColors.readerMenuBackground,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: AppColors.textPrimary.withValues(alpha: 0.12),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: isRTL ? 'Soldan sağa oku' : 'Sağdan sola oku',
            onPressed: onToggleDirection,
            style: IconButton.styleFrom(
              foregroundColor: AppColors.accent,
              backgroundColor: AppColors.surface,
              fixedSize: const Size(48, 48),
              padding: EdgeInsets.zero,
              shape: const CircleBorder(),
            ),
            icon: Icon(
              isRTL
                  ? Icons.format_textdirection_r_to_l
                  : Icons.format_textdirection_l_to_r,
              size: 22,
            ),
          ),
          const SizedBox(height: 6),
          IconButton(
            tooltip: 'Ayarlar',
            onPressed: onOpenSettings,
            style: IconButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              backgroundColor: AppColors.surface,
              fixedSize: const Size(48, 48),
              padding: EdgeInsets.zero,
              shape: const CircleBorder(),
            ),
            icon: const Icon(Icons.settings_outlined, size: 22),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Alt Menü
// ═══════════════════════════════════════════════════════════════════════════════

class _BottomMenu extends StatelessWidget {
  const _BottomMenu({
    required this.currentPage,
    required this.totalPages,
    required this.hasPreviousChapter,
    required this.hasNextChapter,
    required this.onChapterStep,
    required this.onSliderChanged,
    required this.onSliderChangeEnd,
  });

  final int currentPage;
  final int totalPages;
  final bool hasPreviousChapter;
  final bool hasNextChapter;
  final ValueChanged<int> onChapterStep;
  final ValueChanged<double> onSliderChanged;
  final ValueChanged<double> onSliderChangeEnd;

  @override
  Widget build(BuildContext context) {
    final progress = totalPages > 1 ? currentPage / (totalPages - 1) : 0.0;
    final pageLabel = '${currentPage + 1} / $totalPages';

    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.background.withValues(alpha: 0.85),
            border: Border(
              top: BorderSide(
                color: Colors.white.withValues(alpha: 0.08),
                width: 1,
              ),
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x44000000),
                blurRadius: 24,
                offset: Offset(0, -8),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      _ReaderJumpButton(
                        icon: Icons.skip_previous_rounded,
                        tooltip: 'Önceki bölüm',
                        enabled: hasPreviousChapter,
                        onPressed: () => onChapterStep(-1),
                      ),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: AppColors.accent,
                            inactiveTrackColor: Colors.white.withValues(
                              alpha: 0.16,
                            ),
                            thumbColor: AppColors.accent,
                            overlayColor: AppColors.accent.withValues(
                              alpha: 0.18,
                            ),
                            trackHeight: 5,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 9,
                              elevation: 3,
                              pressedElevation: 6,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 20,
                            ),
                            showValueIndicator:
                                ShowValueIndicator.onlyForContinuous,
                            valueIndicatorColor: AppColors.surface,
                            valueIndicatorShape:
                                const PaddleSliderValueIndicatorShape(),
                            valueIndicatorTextStyle: const TextStyle(
                              color: AppColors.accent,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                          child: Slider(
                            value: progress.clamp(0.0, 1.0),
                            label: pageLabel,
                            onChanged: totalPages > 1 ? onSliderChanged : null,
                            onChangeEnd: totalPages > 1
                                ? onSliderChangeEnd
                                : null,
                          ),
                        ),
                      ),
                      _ReaderJumpButton(
                        icon: Icons.skip_next_rounded,
                        tooltip: 'Sonraki bölüm',
                        enabled: hasNextChapter,
                        onPressed: () => onChapterStep(1),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 2),
                    child: Row(
                      children: [
                        const Text(
                          'OKUMA İLERLEMESİ',
                          style: TextStyle(
                            color: AppColors.textDisabled,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.9,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.accent.withValues(alpha: 0.16),
                            ),
                          ),
                          child: Text(
                            pageLabel,
                            style: const TextStyle(
                              color: AppColors.accent,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              fontFeatures: [ui.FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReaderJumpButton extends StatelessWidget {
  const _ReaderJumpButton({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: enabled ? onPressed : null,
      style: IconButton.styleFrom(
        foregroundColor: AppColors.accent,
        disabledForegroundColor: AppColors.textDisabled,
        backgroundColor: Colors.white.withValues(alpha: 0.05),
        fixedSize: const Size(44, 44),
        padding: EdgeInsets.zero,
        shape: const CircleBorder(),
      ),
      icon: Icon(icon, size: 23),
    );
  }
}
