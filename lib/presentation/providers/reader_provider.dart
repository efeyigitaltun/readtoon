import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../core/constants/app_constants.dart';
import '../../data/models/comic_book.dart';
import '../../data/models/read_history.dart';
import 'tracked_series_provider.dart';

// Not: Sayfa isimleri artık doğrudan ReaderScreen'deki
// IComicDecoder.getPageCount() üzerinden alınır.
// PageNamesNotifier kaldırıldı – decoder factory pattern ile gerçeksizleşti.

// ═══════════════════════════════════════════════════════════════════════════════
// Mevcut Sayfa State'i
// ═══════════════════════════════════════════════════════════════════════════════

/// Okuyucudaki mevcut sayfa indeksini yönetir (0 tabanlı).
/// Sayfa değiştiğinde otomatik olarak Hive'a kaydeder.
class CurrentPageNotifier extends Notifier<int> {
  late ComicBook _comic;
  late String _readingMode;

  @override
  int build() => 0;

  /// Okuyucu açıldığında başlatılır: geçmişten sayfa yüklenir.
  void initialize(ComicBook comic, String readingMode) {
    _comic = comic;
    _readingMode = readingMode;

    final box = Hive.box<ReadHistory>(AppConstants.historyBox);
    final history = box.get(comic.id);
    final lastPage = (comic.totalPages - 1).clamp(0, 0x7fffffff);
    state = (history?.currentPage ?? 0).clamp(0, lastPage);
  }

  /// Sayfa değiştiğinde çağrılır; Hive'a kaydeder.
  void goToPage(int pageIndex) {
    if (pageIndex < 0 || pageIndex >= _comic.totalPages || pageIndex == state) {
      return;
    }
    state = pageIndex;
    _saveProgress(pageIndex);
  }

  void nextPage() => goToPage(state + 1);
  void prevPage() => goToPage(state - 1);

  bool get isFirstPage => state == 0;
  bool get isLastPage => state >= _comic.totalPages - 1;

  void _saveProgress(int page) {
    final box = Hive.box<ReadHistory>(AppConstants.historyBox);
    final history = ReadHistory(
      comicId: _comic.id,
      currentPage: page,
      readingMode: _readingMode,
      lastReadAt: DateTime.now(),
    );
    box.put(_comic.id, history);

    final linkedMediaId = _comic.linkedMediaId;
    if (_comic.totalPages > 0 &&
        page >= _comic.totalPages - 1 &&
        linkedMediaId != null) {
      unawaited(_countLinkedChapter(linkedMediaId));
    }
  }

  Future<void> _countLinkedChapter(int mediaId) async {
    try {
      await ref
          .read(trackedSeriesProvider.notifier)
          .countLocalComicCompletion(mediaId: mediaId, comicId: _comic.id);
    } catch (error) {
      // Okuma geçmişi kaydı tamamlanmıştır; takip sayacı hatası okuyucuyu kesmez.
      debugPrint('Bağlı seri bölüm sayacı güncellenemedi: $error');
    }
  }
}

final currentPageProvider = NotifierProvider<CurrentPageNotifier, int>(
  CurrentPageNotifier.new,
);

// ═══════════════════════════════════════════════════════════════════════════════
// Reader Menü Görünürlüğü
// ═══════════════════════════════════════════════════════════════════════════════

/// Tam ekran modunda üst/alt menülerin görünürlüğünü yönetir.
/// Varsayılan: gizli (tam ekran okuma deneyimi).
class ReaderMenuNotifier extends Notifier<bool> {
  @override
  bool build() => false; // Başlangıçta menüler gizli

  void toggle() => state = !state;
  void show() => state = true;
  void hide() => state = false;
}

final readerMenuVisibleProvider = NotifierProvider<ReaderMenuNotifier, bool>(
  ReaderMenuNotifier.new,
);
