import 'package:cloud_firestore/cloud_firestore.dart';

class CommunityReview {
  const CommunityReview({
    required this.userId,
    required this.username,
    required this.rating,
    required this.reviewNote,
    required this.updatedAt,
  });

  final String userId;
  final String username;
  final double rating;
  final String reviewNote;
  final DateTime? updatedAt;

  factory CommunityReview.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    final timestamp = data['updatedAt'];
    final rawRating = data['rating'];

    return CommunityReview(
      userId: data['userId'] as String? ?? document.id,
      username: data['username'] as String? ?? 'ReadToon kullanıcısı',
      rating: rawRating is num ? rawRating.toDouble().clamp(0, 5) : 0,
      reviewNote: data['reviewNote'] as String? ?? '',
      updatedAt: timestamp is Timestamp ? timestamp.toDate() : null,
    );
  }
}
