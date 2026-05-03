import 'package:cloud_firestore/cloud_firestore.dart';

class StoryRepository {
  const StoryRepository();

  Future<void> replaceItemVideos({
    required String sellerId,
    required String sellerName,
    required String sellerPhone,
    required String itemId,
    required String itemName,
    required String itemPrice,
    required List<String> videoUrls,
  }) async {
    final storyRef = FirebaseFirestore.instance
        .collection('stories')
        .doc(sellerId);
    final snapshot = await storyRef.get();
    final existingVideos = _videosWithoutItem(snapshot.data(), itemId);
    final createdAt = Timestamp.now();
    final updatedVideos = [
      ...existingVideos,
      ...videoUrls.map(
        (url) => {
          'url': url,
          'item_id': itemId,
          'item_name': itemName,
          'item_price': itemPrice,
          'created_at': createdAt,
        },
      ),
    ];

    if (updatedVideos.isEmpty) {
      await storyRef.delete();
      return;
    }

    await storyRef.set({
      'seller_uid': sellerId,
      'seller_name': sellerName,
      'seller_phone': sellerPhone,
      'latest_created_at': createdAt,
      'videos': updatedVideos,
    }, SetOptions(merge: true));
  }

  Future<void> removeItemVideos({
    required String sellerId,
    required String itemId,
  }) async {
    final storyRef = FirebaseFirestore.instance
        .collection('stories')
        .doc(sellerId);
    final snapshot = await storyRef.get();
    if (!snapshot.exists) {
      return;
    }

    final remainingVideos = _videosWithoutItem(snapshot.data(), itemId);
    if (remainingVideos.isEmpty) {
      await storyRef.delete();
      return;
    }

    await storyRef.update({
      'videos': remainingVideos,
      'latest_created_at': _latestTimestamp(remainingVideos),
    });
  }

  List<Map<String, dynamic>> _videosWithoutItem(
    Map<String, dynamic>? story,
    String itemId,
  ) {
    final videos = story?['videos'];
    if (videos is! List) {
      return [];
    }

    return videos
        .whereType<Map>()
        .map((video) => Map<String, dynamic>.from(video))
        .where((video) => video['item_id']?.toString() != itemId)
        .toList();
  }

  Object _latestTimestamp(List<Map<String, dynamic>> videos) {
    Timestamp? latest;
    for (final video in videos) {
      final createdAt = video['created_at'];
      if (createdAt is Timestamp &&
          (latest == null || createdAt.compareTo(latest) > 0)) {
        latest = createdAt;
      }
    }
    return latest ?? FieldValue.serverTimestamp();
  }
}
