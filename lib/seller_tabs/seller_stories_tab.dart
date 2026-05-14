import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../story_viewer_page.dart';

class SellerStoriesTab extends StatefulWidget {
  const SellerStoriesTab({super.key});

  @override
  State<SellerStoriesTab> createState() => _SellerStoriesTabState();
}

class _SellerStoriesTabState extends State<SellerStoriesTab> {
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(Duration.zero, () {
      if (mounted) {
        setState(() => _now = DateTime.now());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('stories')
          .orderBy('created_at', descending: true)
          .limit(100)
          .snapshots(includeMetadataChanges: true),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (snapshot.data?.metadata.isFromCache ?? false) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = (snapshot.data?.docs ?? [])
            .where((doc) => (doc.data()['video_url']?.toString() ?? '').isNotEmpty)
            .toList();

        if (docs.isEmpty) {
          return const _EmptyStories();
        }

        return FutureBuilder<List<StorySeller>>(
          future: _storiesFromDocs(docs, _now),
          builder: (context, activeStoriesSnapshot) {
            if (activeStoriesSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final stories = activeStoriesSnapshot.data ?? [];
            if (stories.isEmpty) {
              return const _EmptyStories();
            }

            return StoryViewerPage(
              stories: stories,
              initialStoryIndex: 0,
              showCloseButton: false,
              popOnComplete: false,
            );
          },
        );
      },
    );
  }

  Future<List<StorySeller>> _storiesFromDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    DateTime activeNow,
  ) async {
    final stories = <StorySeller>[];
    for (final doc in docs) {
      final story = doc.data();
      final video = await _storyVideoFromMap(story, activeNow);
      if (video == null) {
        continue;
      }
      stories.add(
        StorySeller(
          sellerName: story['seller_name']?.toString() ?? 'Seller',
          videos: [video],
        ),
      );
    }
    return stories;
  }

  Future<StoryVideo?> _storyVideoFromMap(
    Map<String, dynamic> story,
    DateTime activeNow,
  ) async {
    final itemId = story['item_id']?.toString() ?? '';
    final videoUrl = story['video_url']?.toString() ?? '';
    if (itemId.isEmpty || videoUrl.isEmpty) {
      return null;
    }

    final itemDoc = await FirebaseFirestore.instance
        .collection('items')
        .doc(itemId)
        .get();
    if (!itemDoc.exists) {
      return null;
    }

    final item = itemDoc.data() ?? {};
    if (!_isItemActive(item, activeNow)) {
      return null;
    }

    return StoryVideo(
      url: videoUrl,
      itemId: itemId,
      itemName:
          item['item_name']?.toString() ??
          story['item_name']?.toString() ??
          'Item',
      itemPrice:
          item['item_price']?.toString() ??
          story['item_price']?.toString() ??
          '',
      sellerName: story['seller_name']?.toString() ?? 'Seller',
      sellerPhone: story['seller_phone']?.toString() ?? '',
      itemData: item,
    );
  }

  bool _isItemActive(Map<String, dynamic> item, DateTime now) {
    final createdAt = item['created_at'];
    final timePeriodHours = item['time_period_hours'];
    if (createdAt is Timestamp && timePeriodHours is num) {
      return createdAt
          .toDate()
          .add(Duration(hours: timePeriodHours.toInt()))
          .isAfter(now);
    }
    final expiresAt = item['expires_at'];
    if (expiresAt is Timestamp) {
      return expiresAt.toDate().isAfter(now);
    }
    if (expiresAt is DateTime) {
      return expiresAt.isAfter(now);
    }
    return true;
  }
}

class _EmptyStories extends StatelessWidget {
  const _EmptyStories();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Colors.black,
      child: Center(
        child: Text(
          'No stories available',
          style: TextStyle(color: Colors.white70, fontSize: 16),
        ),
      ),
    );
  }
}
