import 'dart:async';

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
  Timer? _clockTimer;
  bool _isSearchOpen = false;
  bool _isGridView = false;
  String _query = '';
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        setState(() => _now = DateTime.now());
      }
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
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
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('items')
          .orderBy('created_at', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        final isLoading = snapshot.connectionState == ConnectionState.waiting;
        final hasError = snapshot.hasError;
        final docs = _filterDocs(
          (snapshot.data?.docs ?? [])
              .where((doc) => _isItemActive(doc.data(), _now))
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
              ),
            ),
            SliverToBoxAdapter(
              child: _StoryStrip(
                activeNow: _now,
                isGridView: _isGridView,
                onToggleGrid: () {
                  setState(() => _isGridView = !_isGridView);
                },
              ),
            ),
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
                padding: const EdgeInsets.all(16),
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
                            isCompact: true,
                          );
                        },
                      )
                    : SliverList.builder(
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final doc = docs[index];
                          return ItemCard(docId: doc.id, item: doc.data());
                        },
                      ),
              ),
          ],
        );
      },
    );
  }
}

class _StoryStrip extends StatelessWidget {
  const _StoryStrip({
    required this.activeNow,
    required this.isGridView,
    required this.onToggleGrid,
  });

  final DateTime activeNow;
  final bool isGridView;
  final VoidCallback onToggleGrid;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('stories')
          .orderBy('latest_created_at', descending: true)
          .limit(20)
          .snapshots(includeMetadataChanges: true),
      builder: (context, snapshot) {
        if (snapshot.data?.metadata.isFromCache ?? false) {
          return const SizedBox.shrink();
        }

        final docs = (snapshot.data?.docs ?? []).where((doc) {
          final videos = doc.data()['videos'];
          return videos is List && videos.isNotEmpty;
        }).toList();

        if (docs.isEmpty) {
          return const SizedBox.shrink();
        }

        return FutureBuilder<List<_SellerStory>>(
          future: _sellerStoriesFromDocs(docs, activeNow),
          builder: (context, activeStoriesSnapshot) {
            final stories = activeStoriesSnapshot.data ?? [];
            if (stories.isEmpty) {
              return const SizedBox.shrink();
            }

            return Container(
              height: 84,
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
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
                  const SizedBox(width: 10),
                  _GridToggleButton(
                    isGridView: isGridView,
                    onTap: onToggleGrid,
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
    DateTime activeNow,
  ) async {
    final stories = <_SellerStory>[];
    for (final doc in docs) {
      final story = doc.data();
      final videos = await _storyVideosFromMap(story, activeNow);
      if (videos.isEmpty) {
        continue;
      }
      stories.add(
        _SellerStory(
          sellerName: story['seller_name']?.toString() ?? 'Seller',
          videos: videos,
        ),
      );
    }
    return stories;
  }

  Future<List<StoryVideo>> _storyVideosFromMap(
    Map<String, dynamic> story,
    DateTime activeNow,
  ) async {
    final sellerName = story['seller_name']?.toString() ?? 'Seller';
    final sellerPhone = story['seller_phone']?.toString() ?? '';
    final videos = story['videos'];
    if (videos is! List) {
      return [];
    }

    final parsedVideos = videos
        .whereType<Map>()
        .map((video) {
          final data = Map<String, dynamic>.from(video);
          return _StoryVideoData(
            itemId: data['item_id']?.toString() ?? '',
            storyVideo: StoryVideo(
              url: data['url']?.toString() ?? '',
              itemName: data['item_name']?.toString() ?? 'Item',
              itemPrice: data['item_price']?.toString() ?? '',
              sellerName: sellerName,
              sellerPhone: sellerPhone,
            ),
          );
        })
        .where((video) => video.storyVideo.url.isNotEmpty)
        .toList()
        .reversed
        .toList();

    final activeVideos = <StoryVideo>[];
    for (final video in parsedVideos) {
      if (video.itemId.isEmpty) {
        continue;
      }
      final itemDoc = await FirebaseFirestore.instance
          .collection('items')
          .doc(video.itemId)
          .get();
      if (itemDoc.exists) {
        final item = itemDoc.data() ?? {};
        if (!_isItemActive(item, activeNow)) {
          continue;
        }
        activeVideos.add(
          video.storyVideo.copyWith(
            itemName: item['item_name']?.toString(),
            itemPrice: item['item_price']?.toString(),
          ),
        );
      }
    }
    return activeVideos;
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

class _StoryVideoData {
  const _StoryVideoData({required this.itemId, required this.storyVideo});

  final String itemId;
  final StoryVideo storyVideo;
}

class _GridToggleButton extends StatelessWidget {
  const _GridToggleButton({required this.isGridView, required this.onTap});

  final bool isGridView;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 23),
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
  });

  final bool isSearchOpen;
  final TextEditingController searchController;
  final VoidCallback onOpenSearch;
  final VoidCallback onCloseSearch;
  final ValueChanged<String> onQueryChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF25D366),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: SizedBox(
            height: 48,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    AnimatedOpacity(
                      opacity: isSearchOpen ? 0 : 1,
                      duration: const Duration(milliseconds: 160),
                      child: const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'SOOQ ALI',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic,
                        width: isSearchOpen ? constraints.maxWidth : 48,
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
                                      color: Color(0xFF128C4A),
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
                                      color: const Color(0xFF128C4A),
                                    ),
                                  ],
                                )
                              : IconButton(
                                  key: const ValueKey('search-button'),
                                  onPressed: onOpenSearch,
                                  icon: const Icon(Icons.search),
                                  color: const Color(0xFF128C4A),
                                ),
                        ),
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
