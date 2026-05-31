import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../seller_session.dart';
import '../upload_status_manager.dart';
import '../widgets/item_card.dart';

class SellerFeedTab extends StatefulWidget {
  const SellerFeedTab({
    super.key,
    required this.chromeVisibleListenable,
    required this.onSearchActiveChanged,
  });

  final ValueListenable<bool> chromeVisibleListenable;
  final ValueChanged<bool> onSearchActiveChanged;

  @override
  SellerFeedTabState createState() => SellerFeedTabState();
}

class SellerFeedTabState extends State<SellerFeedTab> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _scrollController = ScrollController();
  final Map<String, GlobalKey> _itemKeys = {};
  final Set<String> _seenItemIds = {};
  final Set<String> _pendingSeenItemIds = {};
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _itemsStream =
      FirebaseFirestore.instance
          .collection('items')
          .orderBy('created_at', descending: true)
          .limit(60)
          .snapshots();
  bool _isSearchOpen = false;
  bool _isGridView = true;
  String _query = '';
  Timer? _searchDebounce;
  Timer? _visibilityDebounce;
  Timer? _seenFlushTimer;
  String? _sellerId;
  bool _isLoadingSeenItems = true;
  final DateTime _openedAt = DateTime.now();
  int _refreshTick = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_scheduleVisibleSeenCheck);
    _loadSeenItems();
  }

  @override
  void dispose() {
    widget.onSearchActiveChanged(false);
    _searchDebounce?.cancel();
    _visibilityDebounce?.cancel();
    _seenFlushTimer?.cancel();
    _flushSeenItems();
    _scrollController.dispose();
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSeenItems() async {
    final session = await SellerSession.current();
    if (!mounted) {
      return;
    }
    _sellerId = session?.sellerId;
    final sellerId = _sellerId;
    if (sellerId == null || sellerId.isEmpty) {
      setState(() => _isLoadingSeenItems = false);
      return;
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collectionGroup('viewers')
          .where('seller_id', isEqualTo: sellerId)
          .limit(500)
          .get();
      if (!mounted) {
        return;
      }
      setState(() {
        _seenItemIds
          ..clear()
          ..addAll(snapshot.docs.map((doc) {
            final itemId = doc.data()['item_id']?.toString();
            return itemId?.isNotEmpty == true
                ? itemId!
                : doc.reference.parent.parent?.id ?? '';
          }).where((itemId) => itemId.isNotEmpty));
        _isLoadingSeenItems = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingSeenItems = false);
      }
    }
  }

  void _handleSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 280), () {
      if (mounted) {
        setState(() => _query = value);
      }
    });
  }

  void scrollToTop() {
    if (!_scrollController.hasClients) {
      return;
    }
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _refreshFeed() async {
    setState(() => _refreshTick++);
    await Future<void>.delayed(const Duration(milliseconds: 350));
  }

  void _openSearch() {
    setState(() => _isSearchOpen = true);
    widget.onSearchActiveChanged(true);
  }

  void _closeSearch() {
    _searchFocusNode.unfocus();
    _searchController.clear();
    widget.onSearchActiveChanged(false);
    setState(() {
      _isSearchOpen = false;
      _query = '';
    });
  }

  void _toggleLayoutMode() {
    setState(() => _isGridView = !_isGridView);
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
      final searchableText =
          [item['item_name'], item['item_price'], item['location']]
              .whereType<Object>()
              .map((value) => value.toString().toLowerCase())
              .join(' ');
      return searchableText.contains(query);
    }).toList();
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _rankDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    if (_query.trim().isNotEmpty) {
      return docs;
    }

    final unseenDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    final seenDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final doc in docs) {
      (_seenItemIds.contains(doc.id) ? seenDocs : unseenDocs).add(doc);
    }
    return [...unseenDocs, ...seenDocs];
  }

  void _scheduleVisibleSeenCheck() {
    _visibilityDebounce?.cancel();
    _visibilityDebounce = Timer(
      const Duration(milliseconds: 220),
      _markVisibleItemsSeen,
    );
  }

  void _markVisibleItemsSeen() {
    final sellerId = _sellerId;
    if (sellerId == null || sellerId.isEmpty || !_scrollController.hasClients) {
      return;
    }

    for (final entry in _itemKeys.entries) {
      final itemId = entry.key;
      if (_seenItemIds.contains(itemId) || _pendingSeenItemIds.contains(itemId)) {
        continue;
      }
      if (_isItemCardMostlyVisible(entry.value)) {
        _seenItemIds.add(itemId);
        _pendingSeenItemIds.add(itemId);
      }
    }

    if (_pendingSeenItemIds.isNotEmpty) {
      _seenFlushTimer ??= Timer(
        const Duration(milliseconds: 800),
        _flushSeenItems,
      );
    }
  }

  bool _isItemCardMostlyVisible(GlobalKey key) {
    final context = key.currentContext;
    if (context == null) {
      return false;
    }
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.attached || !renderBox.hasSize) {
      return false;
    }
    final top = renderBox.localToGlobal(Offset.zero).dy;
    final height = renderBox.size.height;
    final bottom = top + height;
    final viewportTop = MediaQuery.paddingOf(context).top + 56;
    final viewportBottom = MediaQuery.sizeOf(context).height - 58;
    final visibleHeight =
        bottom.clamp(viewportTop, viewportBottom) -
        top.clamp(viewportTop, viewportBottom);
    return visibleHeight > 0 && visibleHeight / height >= 0.35;
  }

  Future<void> _flushSeenItems() async {
    _seenFlushTimer?.cancel();
    _seenFlushTimer = null;
    final sellerId = _sellerId;
    if (sellerId == null || sellerId.isEmpty || _pendingSeenItemIds.isEmpty) {
      return;
    }

    final pending = List<String>.from(_pendingSeenItemIds);
    _pendingSeenItemIds.clear();
    try {
      final batch = FirebaseFirestore.instance.batch();
      for (final itemId in pending) {
        final ref = FirebaseFirestore.instance
            .collection('item_seen')
            .doc(itemId)
            .collection('viewers')
            .doc(sellerId);
        batch.set(ref, {
          'item_id': itemId,
          'seller_id': sellerId,
          'seen_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      await batch.commit();
    } catch (_) {
      _pendingSeenItemIds.addAll(pending);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _itemsStream,
          builder: (context, snapshot) {
            final isLoading =
                snapshot.connectionState == ConnectionState.waiting;
            final hasError = snapshot.hasError;
            final docs = _rankDocs(_filterDocs(
              (snapshot.data?.docs ?? [])
                  .where((doc) => _isItemActive(doc.data(), _openedAt))
                  .toList(),
            ));

            WidgetsBinding.instance.addPostFrameCallback((_) {
              _scheduleVisibleSeenCheck();
            });

            return RefreshIndicator(
              color: const Color(0xFFFF7801),
              onRefresh: _refreshFeed,
              child: CustomScrollView(
                key: PageStorageKey(
                  'seller-feed-scroll-${_isGridView ? 'grid' : 'list'}-$_refreshTick',
                ),
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: _FeedHeader(
                      isGridView: _isGridView,
                      onToggleGrid: _toggleLayoutMode,
                    ),
                  ),
                  if (isLoading || _isLoadingSeenItems)
                    SliverPadding(
                      padding: _isGridView
                          ? const EdgeInsets.symmetric(
                              horizontal: 2,
                              vertical: 8,
                            )
                          : const EdgeInsets.symmetric(
                              horizontal: 2,
                              vertical: 12,
                            ),
                      sliver: _isGridView
                          ? const SliverToBoxAdapter(
                              child: _FeedSkeletonGrid(),
                            )
                          : SliverList.builder(
                              itemCount: 3,
                              itemBuilder: (context, index) {
                                return const ItemCardSkeleton();
                              },
                            ),
                    )
                  else if (hasError)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Text('Error: ${snapshot.error}'),
                      ),
                    )
                  else if (docs.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Text(
                          'No items available',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: _isGridView
                          ? const EdgeInsets.symmetric(
                              horizontal: 2,
                              vertical: 8,
                            )
                          : const EdgeInsets.symmetric(
                              horizontal: 2,
                              vertical: 12,
                            ),
                      sliver: _isGridView
                          ? SliverToBoxAdapter(
                              child: _MasonryItemGrid(
                                docs: docs,
                                keyForDoc: _keyForItem,
                              ),
                            )
                          : SliverList.builder(
                              itemCount: docs.length,
                              itemBuilder: (context, index) {
                                final doc = docs[index];
                                return KeyedSubtree(
                                  key: _keyForItem(doc.id),
                                  child: ItemCard(
                                    docId: doc.id,
                                    item: doc.data(),
                                  ),
                                );
                              },
                            ),
                    ),
                ],
              ),
            );
          },
        ),
        Positioned(
          top: 10,
          left: 12,
          right: 12,
          child: Align(
            alignment: Alignment.topRight,
            child: _FloatingFeedSearchControl(
              isSearchOpen: _isSearchOpen,
              searchController: _searchController,
              searchFocusNode: _searchFocusNode,
              onOpenSearch: _openSearch,
              onCloseSearch: _closeSearch,
              onQueryChanged: _handleSearchChanged,
            ),
          ),
        ),
        const Positioned(
          top: 62,
          right: 12,
          child: _UploadStatusBanner(),
        ),
      ],
    );
  }

  GlobalKey _keyForItem(String itemId) {
    return _itemKeys.putIfAbsent(itemId, GlobalKey.new);
  }
}

class _FloatingFeedSearchControl extends StatelessWidget {
  const _FloatingFeedSearchControl({
    required this.isSearchOpen,
    required this.searchController,
    required this.searchFocusNode,
    required this.onOpenSearch,
    required this.onCloseSearch,
    required this.onQueryChanged,
  });

  final bool isSearchOpen;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final VoidCallback onOpenSearch;
  final VoidCallback onCloseSearch;
  final ValueChanged<String> onQueryChanged;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      width: isSearchOpen ? screenWidth - 24 : 44,
      height: 44,
      decoration: BoxDecoration(
        color: isSearchOpen ? Colors.white : const Color(0xFFFF7801),
        borderRadius: BorderRadius.circular(24),
        border: isSearchOpen ? Border.all(color: const Color(0xFFFF7801)) : null,
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: isSearchOpen
            ? Row(
                key: const ValueKey('floating-search-field'),
                children: [
                  const SizedBox(width: 12),
                  const Icon(Icons.search, color: Color(0xFFFF7801)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: searchController,
                      focusNode: searchFocusNode,
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
                key: const ValueKey('floating-search-button'),
                onPressed: onOpenSearch,
                icon: const Icon(Icons.search),
                color: Colors.white,
              ),
      ),
    );
  }
}

class _FeedHeader extends StatelessWidget {
  const _FeedHeader({
    required this.isGridView,
    required this.onToggleGrid,
  });

  final bool isGridView;
  final VoidCallback onToggleGrid;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      color: const Color(0xFFF4FBF7),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Align(
            alignment: Alignment.center,
            child: SizedBox(
              height: 56,
              width: 152,
              child: Image(
                image: AssetImage('assets/branding/logo.png'),
                fit: BoxFit.cover,
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: _GridToggleButton(
              isGridView: isGridView,
              onTap: onToggleGrid,
              bottomPadding: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _MasonryItemGrid extends StatelessWidget {
  const _MasonryItemGrid({required this.docs, required this.keyForDoc});

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final GlobalKey Function(String itemId) keyForDoc;

  @override
  Widget build(BuildContext context) {
    final leftDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    final rightDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];

    for (var i = 0; i < docs.length; i++) {
      if (i.isEven) {
        leftDocs.add(docs[i]);
      } else {
        rightDocs.add(docs[i]);
      }
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _MasonryColumn(docs: leftDocs, keyForDoc: keyForDoc)),
        const SizedBox(width: 4),
        Expanded(child: _MasonryColumn(docs: rightDocs, keyForDoc: keyForDoc)),
      ],
    );
  }
}

class _FeedSkeletonGrid extends StatelessWidget {
  const _FeedSkeletonGrid();

  @override
  Widget build(BuildContext context) {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            children: [
              ItemCardSkeleton(isCompact: true),
              ItemCardSkeleton(isCompact: true),
              ItemCardSkeleton(isCompact: true),
            ],
          ),
        ),
        SizedBox(width: 4),
        Expanded(
          child: Column(
            children: [
              ItemCardSkeleton(isCompact: true),
              ItemCardSkeleton(isCompact: true),
              ItemCardSkeleton(isCompact: true),
            ],
          ),
        ),
      ],
    );
  }
}

class _MasonryColumn extends StatelessWidget {
  const _MasonryColumn({required this.docs, required this.keyForDoc});

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final GlobalKey Function(String itemId) keyForDoc;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: docs.map((doc) {
        return KeyedSubtree(
          key: keyForDoc(doc.id),
          child: ItemCard(docId: doc.id, item: doc.data(), isCompact: true),
        );
      }).toList(),
    );
  }
}

class _UploadStatusBanner extends StatelessWidget {
  const _UploadStatusBanner();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<UploadStatus?>(
      valueListenable: UploadStatusManager.current,
      builder: (context, status, child) {
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: status == null
              ? const SizedBox.shrink()
              : Container(
                  key: ValueKey(status.message),
                  width: 260,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.10),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      _UploadStatusIcon(type: status.type),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          status.message,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }
}

class _UploadStatusIcon extends StatelessWidget {
  const _UploadStatusIcon({required this.type});

  final UploadStatusType type;

  @override
  Widget build(BuildContext context) {
    return switch (type) {
      UploadStatusType.uploading => const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2.4),
      ),
      UploadStatusType.success => const Icon(
        Icons.check_circle,
        color: Color(0xFF25D366),
      ),
      UploadStatusType.error => const Icon(Icons.error, color: Colors.red),
    };
  }
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
        color: const Color(0xFF001341),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 46,
            height: 46,
            child: Icon(
              isGridView ? Icons.view_agenda : Icons.grid_view,
              color: Colors.white,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }
}
