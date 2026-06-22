import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/item_search.dart';
import 'feed_service.dart';

class ItemSearchService {
  ItemSearchService._();

  static final _items = FirebaseFirestore.instance.collection('items');

  static Future<List<FeedItem>> search({
    required String status,
    required String query,
    int limit = 80,
  }) async {
    final normalized = normalizeItemSearchText(query);
    if (normalized.isEmpty) return const [];

    final tokens = normalized
        .split(' ')
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
    if (tokens.isEmpty) return const [];

    final byId = <String, FeedItem>{};
    await _loadKeywordMatches(
      status: status,
      token: tokens.first,
      tokens: tokens,
      limit: limit,
      byId: byId,
    );

    if (byId.length < limit) {
      await _loadRecentFallback(
        status: status,
        tokens: tokens,
        limit: limit,
        byId: byId,
      );
    }

    final results = byId.values.toList(growable: false);
    results.sort((a, b) => _createdAtMs(b.data).compareTo(_createdAtMs(a.data)));
    return results.length > limit ? results.take(limit).toList() : results;
  }

  static Future<void> _loadKeywordMatches({
    required String status,
    required String token,
    required List<String> tokens,
    required int limit,
    required Map<String, FeedItem> byId,
  }) async {
    try {
      final snap = await _items
          .where('status', isEqualTo: status)
          .where('search_keywords', arrayContains: token)
          .limit(limit)
          .get();
      _addMatches(snap.docs, tokens, byId);
    } on FirebaseException {
      // Older projects may need the array-contains index to warm up; fallback
      // keeps search usable without blocking the feed UI.
    }
  }

  static Future<void> _loadRecentFallback({
    required String status,
    required List<String> tokens,
    required int limit,
    required Map<String, FeedItem> byId,
  }) async {
    final snap = await _items
        .where('status', isEqualTo: status)
        .orderBy('created_at', descending: true)
        .limit(limit * 3)
        .get();
    _addMatches(snap.docs, tokens, byId);
  }

  static void _addMatches(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    List<String> tokens,
    Map<String, FeedItem> byId,
  ) {
    final now = DateTime.now();
    for (final doc in docs) {
      if (byId.containsKey(doc.id)) continue;
      final data = doc.data();
      if (!_isActive(data, now) || !_hasUsableMedia(data)) continue;
      final searchText = _searchText(data);
      if (tokens.every(searchText.contains)) {
        byId[doc.id] = FeedItem(id: doc.id, data: data);
      }
    }
  }

  static String _searchText(Map<String, dynamic> data) {
    final stored = normalizeItemSearchText(data['search_text']);
    if (stored.isNotEmpty) return stored;
    return [
      data['item_name'],
      data['location'],
      data['item_price'],
      data['seller_name'],
      data['status'],
      data['price_unit'],
    ].map(normalizeItemSearchText).where((part) => part.isNotEmpty).join(' ');
  }

  static bool _hasUsableMedia(Map<String, dynamic> data) {
    final mediaFiles = data['media_files'];
    if (mediaFiles is List && mediaFiles.any((entry) => entry is Map && entry['url'] != null)) {
      return true;
    }
    final imageUrls = data['image_urls'];
    return imageUrls is List && imageUrls.isNotEmpty;
  }

  static bool _isActive(Map<String, dynamic> data, DateTime now) {
    final expiresAt = data['expires_at'];
    if (expiresAt is Timestamp) return expiresAt.toDate().isAfter(now);
    if (expiresAt is DateTime) return expiresAt.isAfter(now);
    return true;
  }

  static int _createdAtMs(Map<String, dynamic> data) {
    final createdAt = data['created_at'];
    if (createdAt is Timestamp) return createdAt.millisecondsSinceEpoch;
    if (createdAt is DateTime) return createdAt.millisecondsSinceEpoch;
    return 0;
  }
}
