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
    required String location,
    required Timestamp expiresAt,
    required List<Map<String, dynamic>> mediaFiles,
    required List<String> videoUrls,
  }) async {
    await removeItemVideos(sellerId: sellerId, itemId: itemId);

    if (videoUrls.isEmpty) {
      return;
    }

    final batch = FirebaseFirestore.instance.batch();
    final storiesRef = FirebaseFirestore.instance.collection('stories');
    final createdAt = Timestamp.now();

    for (final url in videoUrls) {
      final trimmedUrl = url.trim();
      if (trimmedUrl.isEmpty) {
        continue;
      }

      final storyRef = storiesRef.doc();
      batch.set(storyRef, {
        'seller_uid': sellerId,
        'seller_id': sellerId,
        'seller_name': sellerName,
        'seller_phone': sellerPhone,
        'item_id': itemId,
        'item_name': itemName,
        'item_price': itemPrice,
        'location': location,
        'expires_at': expiresAt,
        'media_files': mediaFiles,
        'video_url': trimmedUrl,
        'created_at': createdAt,
      });
    }

    await batch.commit();
  }

  Future<void> removeItemVideos({
    required String sellerId,
    required String itemId,
  }) async {
    final stories = await FirebaseFirestore.instance
        .collection('stories')
        .where('item_id', isEqualTo: itemId)
        .get();

    if (stories.docs.isEmpty) {
      return;
    }

    final batch = FirebaseFirestore.instance.batch();
    for (final story in stories.docs) {
      batch.delete(story.reference);
    }
    await batch.commit();
  }
}
