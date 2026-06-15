import 'package:cloud_firestore/cloud_firestore.dart';

typedef ItemDocument = QueryDocumentSnapshot<Map<String, dynamic>>;

class ItemStatusCache {
  final List<ItemDocument> docs = [];
  ItemDocument? lastDoc;
  bool isLoading = false;
  bool hasMore = true;
  Object? error;

  void reset() {
    docs.clear();
    lastDoc = null;
    isLoading = false;
    hasMore = true;
    error = null;
  }

  void addUnique(Iterable<ItemDocument> newDocs) {
    final existingIds = docs.map((doc) => doc.id).toSet();
    docs.addAll(newDocs.where((doc) => !existingIds.contains(doc.id)));
  }

  void removeDoc(String docId) {
    docs.removeWhere((doc) => doc.id == docId);
  }
}

class ItemStatusCaches {
  final ItemStatusCache post = ItemStatusCache();
  final ItemStatusCache live = ItemStatusCache();

  ItemStatusCache forStatus(String status) {
    return status == 'live' ? live : post;
  }

  void resetStatus(String status) {
    forStatus(status).reset();
  }

  void resetAll() {
    post.reset();
    live.reset();
  }

  void removeDoc(String docId) {
    post.removeDoc(docId);
    live.removeDoc(docId);
  }
}
