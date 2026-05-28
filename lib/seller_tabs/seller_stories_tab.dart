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
    final now = Timestamp.now();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('stories')
          .where('expires_at', isGreaterThan: now)
          .orderBy('expires_at')
          .limit(100)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        final docs = (snapshot.data?.docs ?? [])
            .where((doc) => (doc.data()['video_url']?.toString() ?? '').isNotEmpty)
            .toList();

        if (docs.isEmpty) {
          return const _EmptyStories();
        }

        final stories = _storiesFromDocs(docs, _now);
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
  }

  List<StorySeller> _storiesFromDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    DateTime activeNow,
  ) {
    final stories = <StorySeller>[];
    for (final doc in docs) {
      final story = doc.data();
      final video = _storyVideoFromMap(story, activeNow);
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

  StoryVideo? _storyVideoFromMap(
    Map<String, dynamic> story,
    DateTime activeNow,
  ) {
    final itemId = story['item_id']?.toString() ?? '';
    final videoUrl = story['video_url']?.toString() ?? '';
    if (itemId.isEmpty || videoUrl.isEmpty) {
      return null;
    }

    if (!_isItemActive(story, activeNow)) {
      return null;
    }
    final sellerPhone =
        story['seller_phone']?.toString() ??
        '';
    final item = Map<String, dynamic>.from(story);
    item['seller_uid'] = story['seller_uid'] ?? story['seller_id'];

    return StoryVideo(
      url: videoUrl,
      itemId: itemId,
      itemName: story['item_name']?.toString() ?? 'Item',
      itemPrice: story['item_price']?.toString() ?? '',
      location: story['location']?.toString() ?? '',
      sellerName: story['seller_name']?.toString() ?? 'Seller',
      sellerPhone: sellerPhone,
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
