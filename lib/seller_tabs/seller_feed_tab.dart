import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../story_viewer_page.dart';
import '../widgets/item_card.dart';

class SellerFeedTab extends StatefulWidget {
  const SellerFeedTab({super.key});

  @override
  State<SellerFeedTab> createState() => _SellerFeedTabState();
}

class _SellerFeedTabState extends State<SellerFeedTab> {
  final _searchController = TextEditingController();
  bool _isSearchOpen = false;
  bool _isGridView = false;
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openSearch() {
    setState(() => _isSearchOpen = true);
  }

  void _closeSearch() {
    _searchController.clear();
    setState(() {
      _isSearchOpen = false;
      _query = '';
    });
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filterDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) {
      return docs;
    }

    return docs.where((doc) {
      final item = doc.data();
      final searchableText = [
        item['item_name'],
        item['item_price'],
        item['origin'],
        item['location'],
      ].whereType<Object>().map((value) => value.toString().toLowerCase()).join(
        ' ',
      );
      return searchableText.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('items')
          .orderBy('created_at', descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snapshot) {
        final isLoading = snapshot.connectionState == ConnectionState.waiting;
        final hasError = snapshot.hasError;
        final docs = _filterDocs(
          (snapshot.data?.docs ?? [])
              .where((doc) => _isItemActive(doc.data(), now))
              .toList(),
        );

        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _FeedHeader(
                isSearchOpen: _isSearchOpen,
                searchController: _searchController,
                onOpenSearch: _openSearch,
                onCloseSearch: _closeSearch,
                onQueryChanged: (value) => setState(() => _query = value),
                isGridView: _isGridView,
                onToggleGrid: () {
                  setState(() => _isGridView = !_isGridView);
                },
              ),
            ),
            const SliverToBoxAdapter(child: _StoryStrip()),
            if (isLoading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (hasError)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('Error: ${snapshot.error}')),
              )
            else if (docs.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(
                    'No items available',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: _isGridView
                    ? const EdgeInsets.all(16)
                    : const EdgeInsets.symmetric(horizontal: 2, vertical: 12),
                sliver: _isGridView
                    ? SliverGrid.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                              childAspectRatio: 0.48,
                            ),
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final doc = docs[index];
                          return ItemCard(
                            docId: doc.id,
                            item: doc.data(),
                            now: now,
                            isCompact: true,
                          );
                        },
                      )
                    : SliverList.builder(
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final doc = docs[index];
                          return ItemCard(
                            docId: doc.id,
                            item: doc.data(),
                            now: now,
                          );
                        },
                      ),
              ),
          ],
        );
      },
    );
  }
}

class _StoryStrip extends StatefulWidget {
  const _StoryStrip();

  @override
  State<_StoryStrip> createState() => _StoryStripState();
}

class _StoryStripState extends State<_StoryStrip> {
  String _cachedDocsKey = '';
  Future<List<_SellerStory>>? _storiesFuture;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('stories')
          .orderBy('created_at', descending: true)
          .limit(20)
          .snapshots(),
      builder: (context, snapshot) {
        final docs = (snapshot.data?.docs ?? [])
            .where((doc) => (doc.data()['video_url']?.toString() ?? '').isNotEmpty)
            .toList();

        if (docs.isEmpty) {
          return const SizedBox.shrink();
        }

        final docsKey = docs.map((doc) => doc.id).join(',');
        if (docsKey != _cachedDocsKey) {
          _cachedDocsKey = docsKey;
          _storiesFuture = _sellerStoriesFromDocs(docs);
        }

        return FutureBuilder<List<_SellerStory>>(
          future: _storiesFuture,
          builder: (context, activeStoriesSnapshot) {
            final stories = activeStoriesSnapshot.data ?? [];
            if (stories.isEmpty) {
              return const SizedBox.shrink();
            }

            return Container(
              height: 72,
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
              child: Row(
                children: [
                  Expanded(
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: stories.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 14),
                      itemBuilder: (context, index) {
                        return _StoryCircle(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => StoryViewerPage(
                                  stories: stories
                                      .map(
                                        (story) => StorySeller(
                                          sellerName: story.sellerName,
                                          videos: story.videos,
                                        ),
                                      )
                                      .toList(),
                                  initialStoryIndex: index,
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<List<_SellerStory>> _sellerStoriesFromDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    final itemIds = <String>{};
    for (final doc in docs) {
      final id = doc.data()['item_id']?.toString() ?? '';
      if (id.isNotEmpty) {
        itemIds.add(id);
      }
    }

    final itemsById = <String, Map<String, dynamic>>{};
    final idList = itemIds.toList();
    for (var i = 0; i < idList.length; i += 10) {
      final chunk = idList.sublist(
        i,
        i + 10 > idList.length ? idList.length : i + 10,
      );
      final query = await FirebaseFirestore.instance
          .collection('items')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final itemDoc in query.docs) {
        itemsById[itemDoc.id] = itemDoc.data();
      }
    }

    final activeNow = DateTime.now();
    final stories = <_SellerStory>[];
    for (final doc in docs) {
      final story = doc.data();
      final itemId = story['item_id']?.toString() ?? '';
      final videoUrl = story['video_url']?.toString() ?? '';
      if (itemId.isEmpty || videoUrl.isEmpty) {
        continue;
      }
      final item = itemsById[itemId];
      if (item == null || !_isItemActive(item, activeNow)) {
        continue;
      }
      stories.add(
        _SellerStory(
          sellerName: story['seller_name']?.toString() ?? 'Seller',
          videos: [
            StoryVideo(
              url: videoUrl,
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
            ),
          ],
        ),
      );
    }
    return stories;
  }
}

bool _isItemActive(Map<String, dynamic> item, DateTime now) {
  final expiresAt = item['expires_at'];
  if (expiresAt is Timestamp) {
    return expiresAt.toDate().isAfter(now);
  }
  if (expiresAt is DateTime) {
    return expiresAt.isAfter(now);
  }
  return true;
}

class _SellerStory {
  const _SellerStory({required this.sellerName, required this.videos});

  final String sellerName;
  final List<StoryVideo> videos;
}

class _GridToggleButton extends StatelessWidget {
  const _GridToggleButton({
    required this.isGridView,
    required this.onTap,
    this.bottomPadding = 23,
  });

  final bool isGridView;
  final VoidCallback onTap;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: Material(
        color: const Color(0xFF1877F2),
        shape: const CircleBorder(),
        elevation: 3,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 46,
            height: 46,
            child: Icon(
              isGridView ? Icons.grid_view : Icons.view_agenda,
              color: Colors.white,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }
}

class _StoryCircle extends StatelessWidget {
  const _StoryCircle({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: SizedBox(
        width: 64,
        child: Center(
          child: Container(
            width: 60,
            height: 60,
            padding: const EdgeInsets.all(3),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Color(0xFF25D366), Color(0xFF0A84FF)],
              ),
            ),
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.person,
                color: Color(0xFF128C4A),
                size: 34,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FeedHeader extends StatelessWidget {
  const _FeedHeader({
    required this.isSearchOpen,
    required this.searchController,
    required this.onOpenSearch,
    required this.onCloseSearch,
    required this.onQueryChanged,
    required this.isGridView,
    required this.onToggleGrid,
  });

  final bool isSearchOpen;
  final TextEditingController searchController;
  final VoidCallback onOpenSearch;
  final VoidCallback onCloseSearch;
  final ValueChanged<String> onQueryChanged;
  final bool isGridView;
  final VoidCallback onToggleGrid;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFFF7801),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: SizedBox(
            height: 48,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    const Align(
                      alignment: Alignment.center,
                      child: Text(
                        'BIZ SOOQ',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic,
                        width: isSearchOpen ? constraints.maxWidth - 56 : 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.16),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          child: isSearchOpen
                              ? Row(
                                  key: const ValueKey('search-field'),
                                  children: [
                                    const SizedBox(width: 12),
                                    const Icon(
                                      Icons.search,
                                      color: Color(0xFFFF7801),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: TextField(
                                        controller: searchController,
                                        autofocus: true,
                                        onChanged: onQueryChanged,
                                        decoration: const InputDecoration(
                                          hintText: 'Search items...',
                                          border: InputBorder.none,
                                          isDense: true,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: onCloseSearch,
                                      icon: const Icon(Icons.close),
                                      color: const Color(0xFFFF7801),
                                    ),
                                  ],
                                )
                              : IconButton(
                                  key: const ValueKey('search-button'),
                                  onPressed: onOpenSearch,
                                  icon: const Icon(Icons.search),
                                  color: const Color(0xFFFF7801),
                                ),
                        ),
                      ),
                    ),
                    if (!isSearchOpen)
                      Align(
                        alignment: Alignment.centerRight,
                        child: _GridToggleButton(
                          isGridView: isGridView,
                          onTap: onToggleGrid,
                          bottomPadding: 0,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
