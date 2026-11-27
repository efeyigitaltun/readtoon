import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/community_review.dart';

/// Her kullanıcının seri başına tek bir güncel puan/incelemesi bulunur.
class FirestoreReviewService {
  FirestoreReviewService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestoreOverride = firestore,
      _authOverride = auth;

  final FirebaseFirestore? _firestoreOverride;
  final FirebaseAuth? _authOverride;

  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;
  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;

  Future<void> saveReview({
    required int mediaId,
    required double rating,
    required String? reviewNote,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'unauthenticated',
        message: 'İnceleme kaydetmek için giriş yapmalısınız.',
      );
    }

    final profile = await _firestore.collection('users').doc(user.uid).get();
    final profileUsername = profile.data()?['username'] as String?;
    final fallbackUsername = user.email?.split('@').first ?? 'ReadToon';
    final resolvedUsername = profileUsername?.trim().isNotEmpty == true
        ? profileUsername!.trim()
        : user.displayName?.trim().isNotEmpty == true
        ? user.displayName!.trim()
        : fallbackUsername;
    final username = resolvedUsername.length > 24
        ? resolvedUsername.substring(0, 24)
        : resolvedUsername;

    final review = _firestore
        .collection('series_reviews')
        .doc(mediaId.toString())
        .collection('reviews')
        .doc(user.uid);

    final batch = _firestore.batch();
    batch.set(review, {
      'userId': user.uid,
      'username': username,
      'rating': (rating.clamp(0.0, 5.0) * 2).round() / 2,
      'reviewNote': reviewNote?.trim() ?? '',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    batch.set(
      _firestore
          .collection('users')
          .doc(user.uid)
          .collection('review_index')
          .doc(mediaId.toString()),
      {'mediaId': mediaId, 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  Future<void> reportReview({
    required int mediaId,
    required CommunityReview review,
    required String reason,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'unauthenticated',
        message: 'İncelemeyi bildirmek için giriş yapmalısınız.',
      );
    }
    if (review.userId == user.uid) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'invalid-argument',
        message: 'Kendi incelemenizi bildiremezsiniz.',
      );
    }

    await _firestore
        .collection('review_reports')
        .doc('${mediaId}_${review.userId}_${user.uid}')
        .set({
          'reporterId': user.uid,
          'mediaId': mediaId,
          'reviewUserId': review.userId,
          'reviewId': review.userId,
          'reason': reason.trim(),
          'createdAt': FieldValue.serverTimestamp(),
        });
  }

  Stream<List<CommunityReview>> watchReviews(int mediaId) {
    return _firestore
        .collection('series_reviews')
        .doc(mediaId.toString())
        .collection('reviews')
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(CommunityReview.fromFirestore)
              .toList(growable: false),
        );
  }
}
