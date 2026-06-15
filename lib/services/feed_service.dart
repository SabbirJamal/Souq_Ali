import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

class FeedService {
  FeedService._();

  static final _functions = FirebaseFunctions.instanceFor(region: 'us-central1');
  static final _feedCallable = _functions.httpsCallable('getFeedItems');
  static final _seenCallable = _functions.httpsCallable('markFeedItemsSeen');
  static final Map<String, Future<FeedPageResult>> _warmupRequests = {};
  static final Map<String, FeedPageResult> _warmupResults = {};
  static final Set<String> _consumedWarmups = {};

  static void warmUpItems({
    required String viewerId,
    required String status,
    int limit = 60,
  }) {
    final key = _warmupKey(
      viewerId: viewerId,
      status: status,
      limit: limit,
    );
    if (_warmupResults.containsKey(key) || _warmupRequests.containsKey(key)) {
      return;
    }

    final request = _fetchItems(
      viewerId: viewerId,
      status: status,
      limit: limit,
    );
    _warmupRequests[key] = request;
    request.then((result) {
      if (!_consumedWarmups.remove(key)) {
        _warmupResults[key] = result;
      }
    }).catchError((_) {
      _consumedWarmups.remove(key);
    }).whenComplete(() {
      _warmupRequests.remove(key);
    });
  }

  static Future<FeedPageResult> fetchItems({
    required String viewerId,
    required String status,
    FeedCursor? cursor,
    int limit = 60,
    bool useWarmup = true,
  }) async {
    if (cursor == null && useWarmup) {
      final key = _warmupKey(
        viewerId: viewerId,
        status: status,
        limit: limit,
      );
      final cachedResult = _warmupResults.remove(key);
      if (cachedResult != null) return cachedResult;

      final pendingRequest = _warmupRequests[key];
      if (pendingRequest != null) {
        _consumedWarmups.add(key);
        return pendingRequest;
      }
    }

    return _fetchItems(
      viewerId: viewerId,
      status: status,
      cursor: cursor,
      limit: limit,
    );
  }

  static Future<FeedPageResult> _fetchItems({
    required String viewerId,
    required String status,
    FeedCursor? cursor,
    int limit = 60,
  }) async {
    final result = await _feedCallable.call<Map<String, dynamic>>({
      'viewerId': viewerId,
      'status': status,
      'cursor': cursor?.toMap(),
      'limit': limit,
    });

    final data = Map<String, dynamic>.from(result.data);
    final rawItems = (data['items'] as List? ?? const []);
    final items = rawItems
        .whereType<Map>()
        .map((item) => FeedItem.fromMap(Map<String, dynamic>.from(item)))
        .toList(growable: false);

    final rawCursor = data['cursor'];
    return FeedPageResult(
      items: items,
      cursor: rawCursor is Map
          ? FeedCursor.fromMap(Map<String, dynamic>.from(rawCursor))
          : null,
      hasMore: data['hasMore'] == true,
    );
  }

  static Future<void> markItemsSeen({
    required String viewerId,
    required String viewerType,
    required List<String> itemIds,
  }) async {
    if (viewerId.isEmpty || itemIds.isEmpty) return;
    await _seenCallable.call<void>({
      'viewerId': viewerId,
      'viewerType': viewerType,
      'itemIds': itemIds,
    });
  }

  static String _warmupKey({
    required String viewerId,
    required String status,
    required int limit,
  }) {
    return '$viewerId|$status|$limit';
  }
}

class FeedPageResult {
  const FeedPageResult({
    required this.items,
    required this.cursor,
    required this.hasMore,
  });

  final List<FeedItem> items;
  final FeedCursor? cursor;
  final bool hasMore;
}

class FeedItem {
  const FeedItem({required this.id, required this.data});

  factory FeedItem.fromMap(Map<String, dynamic> map) {
    return FeedItem(
      id: map['id']?.toString() ?? '',
      data: _restoreTimestamps(
        Map<String, dynamic>.from(map['data'] as Map? ?? const {}),
      ),
    );
  }

  final String id;
  final Map<String, dynamic> data;
}

class FeedCursor {
  const FeedCursor({required this.createdAtMs, required this.docId});

  factory FeedCursor.fromMap(Map<String, dynamic> map) {
    return FeedCursor(
      createdAtMs: (map['createdAtMs'] as num?)?.toInt() ?? 0,
      docId: map['docId']?.toString() ?? '',
    );
  }

  final int createdAtMs;
  final String docId;

  Map<String, dynamic> toMap() => {
        'createdAtMs': createdAtMs,
        'docId': docId,
      };
}

Map<String, dynamic> _restoreTimestamps(Map<String, dynamic> data) {
  return data.map((key, value) => MapEntry(key, _restoreValue(value)));
}

Object? _restoreValue(Object? value) {
  if (value is Map) {
    final map = Map<String, dynamic>.from(value);
    final timestampMs = map['__timestampMs'];
    if (timestampMs is num) {
      return Timestamp.fromMillisecondsSinceEpoch(timestampMs.toInt());
    }
    return _restoreTimestamps(map);
  }
  if (value is List) {
    return value.map(_restoreValue).toList(growable: false);
  }
  return value;
}
