import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/community_review.dart';
import '../../data/services/firestore_review_service.dart';

final firestoreReviewServiceProvider = Provider<FirestoreReviewService>(
  (ref) => FirestoreReviewService(),
);

final communityReviewsProvider =
    StreamProvider.family<List<CommunityReview>, int>((ref, mediaId) {
      try {
        return ref.watch(firestoreReviewServiceProvider).watchReviews(mediaId);
      } catch (error, stackTrace) {
        return Stream<List<CommunityReview>>.error(error, stackTrace);
      }
    });
