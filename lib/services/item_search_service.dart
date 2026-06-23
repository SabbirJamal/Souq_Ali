import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/item_search.dart';
import 'feed_service.dart';

class ItemSearchService {
  ItemSearchService._();

  static const _algoliaApplicationId = 'ZI4NULCVNS';
  static const _algoliaSearchApiKey = 'e7b13c4d229246c6c2aaac090014a3fe';
  static const _algoliaIndexName = 'bizsooq';
  static final _items = FirebaseFirestore.instance.collection('items');
  static final _httpClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 4);

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

    final algoliaResults = await _searchAlgolia(
      status: status,
      query: normalized,
      limit: limit,
    );
    if (algoliaResults.isNotEmpty) {
      return algoliaResults;
    }

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

  static Future<List<FeedItem>> _searchAlgolia({
    required String status,
    required String query,
    required int limit,
  }) async {
    try {
      final uri = Uri.https(
        '$_algoliaApplicationId-dsn.algolia.net',
        '/1/indexes/$_algoliaIndexName/query',
      );
      final request = await _httpClient.postUrl(uri);
      request.headers
        ..contentType = ContentType.json
        ..set('X-Algolia-Application-Id', _algoliaApplicationId)
        ..set('X-Algolia-API-Key', _algoliaSearchApiKey);
      request.write(jsonEncode({
        'query': query,
        'hitsPerPage': limit,
        'filters': 'status:$status AND seller_status:active',
      }));

      final response = await request.close().timeout(const Duration(seconds: 6));
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugLogSearchFallback('Algolia search failed ${response.statusCode}: $body');
        return const [];
      }

      final data = jsonDecode(body);
      final hits = data is Map ? data['hits'] : null;
      if (hits is! List) return const [];

      final now = DateTime.now();
      return hits
          .whereType<Map>()
          .map((hit) {
            final id = hit['objectID']?.toString() ?? '';
            final item = Map<String, dynamic>.from(hit);
            item.remove('_highlightResult');
            item.remove('_rankingInfo');
            item.remove('_snippetResult');
            item.remove('objectID');
            return id.isEmpty ? null : FeedItem(id: id, data: _restoreAlgoliaItem(item));
          })
          .whereType<FeedItem>()
          .where((item) => _isActive(item.data, now) && _hasUsableMedia(item.data))
          .toList(growable: false);
    } catch (error) {
      debugLogSearchFallback('Algolia search fallback: $error');
      return const [];
    }
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
      if (!_isSellerActive(data) || !_isActive(data, now) || !_hasUsableMedia(data)) continue;
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

  static bool _isSellerActive(Map<String, dynamic> data) {
    final status = data['seller_status']?.toString().trim();
    return status == null || status.isEmpty || status == 'active';
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

Map<String, dynamic> _restoreAlgoliaItem(Map<String, dynamic> data) {
  return data.map((key, value) => MapEntry(key, _restoreAlgoliaValue(value)));
}

Object? _restoreAlgoliaValue(Object? value) {
  if (value is Map) {
    final map = Map<String, dynamic>.from(value);
    final timestampMs = map['__timestampMs'];
    if (timestampMs is num) {
      return Timestamp.fromMillisecondsSinceEpoch(timestampMs.toInt());
    }
    return _restoreAlgoliaItem(map);
  }
  if (value is List) {
    return value.map(_restoreAlgoliaValue).toList(growable: false);
  }
  return value;
}

void debugLogSearchFallback(String message) {
  assert(() {
    // ignore: avoid_print
    print(message);
    return true;
  }());
}
