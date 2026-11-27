import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:hive/hive.dart';

import '../../core/constants/app_constants.dart';
import '../models/tracked_series.dart';

/// Restores and synchronizes a user's tracked series with their Firestore library.
class FirestoreSyncService {
  FirestoreSyncService({FirebaseFirestore? firestore})
    : _firestoreOverride = firestore;

  final FirebaseFirestore? _firestoreOverride;
  final Map<String, Future<void>> _inFlightSyncs = {};

  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;

  Future<void> syncForUser(String uid) {
    final activeSync = _inFlightSyncs[uid];
    if (activeSync != null) return activeSync;

    late final Future<void> sync;
    sync = _syncForUser(uid).whenComplete(() {
      if (identical(_inFlightSyncs[uid], sync)) {
        _inFlightSyncs.remove(uid);
      }
    });
    _inFlightSyncs[uid] = sync;
    return sync;
  }

  Future<void> _syncForUser(String uid) async {
    final trackedBox = Hive.box<TrackedSeries>(AppConstants.trackedSeriesBox);
    final settingsBox = Hive.box<dynamic>(AppConstants.settingsBox);
    final ownerUid =
        settingsBox.get(AppConstants.settingsKeyTrackedSeriesOwnerUid)
            as String?;
    final canMergeLocalData = ownerUid == null || ownerUid == uid;

    final library = _firestore
        .collection('users')
        .doc(uid)
        .collection('library');
    final remoteSnapshot = await library.get();
    final merged = <int, TrackedSeries>{};
    final localChangesToUpload = <int, TrackedSeries>{};

    for (final document in remoteSnapshot.docs) {
      final series = _seriesFromMap(document.id, document.data());
      if (series != null) merged[series.mediaId] = series;
    }

    if (canMergeLocalData) {
      for (final localSeries in trackedBox.values) {
        final remoteSeries = merged[localSeries.mediaId];
        if (remoteSeries == null ||
            localSeries.updatedAt.isAfter(remoteSeries.updatedAt)) {
          merged[localSeries.mediaId] = localSeries;
          localChangesToUpload[localSeries.mediaId] = localSeries;
        }
      }
    }

    final restored = merged.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await trackedBox.clear();
    if (restored.isNotEmpty) {
      await trackedBox.putAll({
        for (final series in restored) series.mediaId: series,
      });
    }
    await settingsBox.put(AppConstants.settingsKeyTrackedSeriesOwnerUid, uid);

    await _writeSeriesInBatches(library, localChangesToUpload.values.toList());
  }

  /// Writes local changes after Hive has already accepted them.
  /// A previous account's local cache is never uploaded to a different UID.
  Future<void> upsertSeries(String uid, TrackedSeries series) async {
    final settingsBox = Hive.box<dynamic>(AppConstants.settingsBox);
    var ownerUid =
        settingsBox.get(AppConstants.settingsKeyTrackedSeriesOwnerUid)
            as String?;
    if (ownerUid != null && ownerUid != uid) {
      final activeSync = _inFlightSyncs[uid];
      if (activeSync == null) return;
      try {
        await activeSync;
      } catch (_) {
        return;
      }
      ownerUid =
          settingsBox.get(AppConstants.settingsKeyTrackedSeriesOwnerUid)
              as String?;
      if (ownerUid != uid) return;
    }

    await _firestore
        .collection('users')
        .doc(uid)
        .collection('library')
        .doc(series.mediaId.toString())
        .set(_seriesToMap(series), SetOptions(merge: true));

    if (ownerUid == null) {
      await settingsBox.put(AppConstants.settingsKeyTrackedSeriesOwnerUid, uid);
    }
  }

  Future<void> _writeSeriesInBatches(
    CollectionReference<Map<String, dynamic>> library,
    List<TrackedSeries> series,
  ) async {
    for (var start = 0; start < series.length; start += 450) {
      final batch = _firestore.batch();
      final end = (start + 450).clamp(0, series.length);
      for (final item in series.sublist(start, end)) {
        batch.set(
          library.doc(item.mediaId.toString()),
          _seriesToMap(item),
          SetOptions(merge: true),
        );
      }
      await batch.commit();
    }
  }

  Map<String, Object?> _seriesToMap(TrackedSeries series) => {
    'mediaId': series.mediaId,
    'title': series.title,
    'coverUrl': series.coverUrl,
    'bannerUrl': series.bannerUrl,
    'status': series.status.name,
    'rating': series.rating,
    'chaptersRead': series.chaptersRead,
    'totalChapters': series.totalChapters,
    'reviewNote': series.reviewNote,
    'isFavorite': series.isFavorite,
    'completedLocalComicIds': series.completedLocalComicIds,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  TrackedSeries? _seriesFromMap(String documentId, Map<String, dynamic> data) {
    final parsedId = int.tryParse(documentId);
    final mediaId = _asInt(data['mediaId']) ?? parsedId;
    if (mediaId == null || mediaId <= 0) return null;

    final rawDate = data['updatedAt'];
    final updatedAt = switch (rawDate) {
      Timestamp value => value.toDate(),
      DateTime value => value,
      String value =>
        DateTime.tryParse(value) ?? DateTime.fromMillisecondsSinceEpoch(0),
      _ => DateTime.fromMillisecondsSinceEpoch(0),
    };
    final completedIds = data['completedLocalComicIds'];

    return TrackedSeries(
      mediaId: mediaId,
      title: data['title'] as String? ?? '',
      coverUrl: data['coverUrl'] as String? ?? '',
      bannerUrl: data['bannerUrl'] as String?,
      status: TrackedSeriesStatus.fromStorage(data['status']),
      rating: data['rating'] is num ? (data['rating'] as num).toDouble() : 0,
      chaptersRead: _asInt(data['chaptersRead']) ?? 0,
      totalChapters: _asInt(data['totalChapters']),
      reviewNote: data['reviewNote'] as String?,
      updatedAt: updatedAt,
      completedLocalComicIds: completedIds is List
          ? completedIds.whereType<String>().toList()
          : const [],
      isFavorite: data['isFavorite'] as bool? ?? false,
    );
  }

  int? _asInt(Object? value) => value is num ? value.toInt() : null;
}
