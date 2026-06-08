import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/feed_service.dart';
import '../seller_session.dart';
import '../upload_status_manager.dart';
import '../widgets/item_card.dart';

class SellerFeedTab extends StatefulWidget {
  const SellerFeedTab({
    super.key,
    this.chromeVisibleListenable,
    required this.onSearchActiveChanged,
    this.itemStatus = 'post',
    this.emptyMessage = 'No items available',
  });

  final ValueListenable<bool>? chromeVisibleListenable;
  final ValueChanged<bool> onSearchActiveChanged;
  final String itemStatus;
  final String emptyMessage;

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

  final List<FeedItem> _allDocs = [];
  bool _isGridView = true;
  bool _isSearchOpen = false;
  bool _isLoading = false;
  bool _isMergingLatest = false;
  bool _hasMore = true;
  String _query = '';
  Timer? _searchDebounce;
  Timer? _visibilityDebounce;
  Timer? _seenFlushTimer;
  String? _viewerId;
  String? _viewerType;
  FeedCursor? _feedCursor;
  final DateTime _openedAt = DateTime.now();
  int _refreshTick = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadInitial();
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _isLoading || !_hasMore) return;
    final pos = _scrollController.position.pixels;
    final max = _scrollController.position.maxScrollExtent;
    if (pos > max - 800) {
      _loadMore();
    }
  }

  Future<void> _loadInitial() async {
    if (_isLoading) return;
    await _fetchPage(isInitial: true);
  }

  Future<void> _loadMore() async {
    if (_isLoading || !_hasMore || _isSearchOpen) return;
    await _fetchPage(isInitial: false);
  }

  void _maybeLoadMoreFromBuilder(int index, int total) {
    if (total - index > 8 || _isLoading || !_hasMore || _isSearchOpen) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadMore();
    });
  }

  Future<void> _fetchPage({required bool isInitial}) async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final viewer = await _ensureViewerIdentity();
      if (!mounted) return;
      final viewerId = viewer?.id;
      if (viewerId == null || viewerId.isEmpty) {
        setState(() => _isLoading = false);
        return;
      }

      final result = await FeedService.fetchItems(
        viewerId: viewerId,
        status: widget.itemStatus,
        cursor: isInitial ? null : _feedCursor,
        limit: 60,
      );
      if (!mounted) return;
      setState(() {
        if (isInitial) {
          _allDocs.clear();
        }
        final existingIds = _allDocs.map((doc) => doc.id).toSet();
        _allDocs.addAll(result.items.where((doc) => !existingIds.contains(doc.id)));
        _feedCursor = result.cursor;
        _hasMore = result.hasMore;
        _isLoading = false;
      });
    } catch (error, stackTrace) {
      debugPrint('Feed load failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
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

  Future<_FeedViewerIdentity?> _ensureViewerIdentity() async {
    if (_viewerId != null && _viewerId!.isNotEmpty && _viewerType != null) {
      return _FeedViewerIdentity(id: _viewerId!, type: _viewerType!);
    }
    final viewer = await _resolveViewerIdentity();
    if (!mounted) return null;
    _viewerId = viewer?.id;
    _viewerType = viewer?.type;
    return viewer;
  }

  Future<_FeedViewerIdentity?> _resolveViewerIdentity() async {
    final session = await SellerSession.current();
    final sellerId = session?.sellerId.trim();
    if (sellerId != null && sellerId.isNotEmpty) {
      return _FeedViewerIdentity(id: sellerId, type: 'seller');
    }

    try {
      final auth = FirebaseAuth.instance;
      final user = auth.currentUser ?? (await auth.signInAnonymously()).user;
      final uid = user?.uid;
      if (uid == null || uid.isEmpty) return null;
      return _FeedViewerIdentity(id: uid, type: 'anonymous');
    } catch (_) {
      return null;
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
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(0, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
  }

  Future<void> _refreshFeed() async {
    _markVisibleItemsSeen();
    await _flushSeenItems();
    setState(() {
      _refreshTick++;
      _hasMore = true;
      _feedCursor = null;
    });
    await _fetchPage(isInitial: true);
  }

  Future<void> reloadItems() => _refreshFeed();

  Future<void> mergeLatestItems() async {
    if (_isLoading || _isMergingLatest) return;
    _isMergingLatest = true;
    final viewer = await _ensureViewerIdentity();
    if (!mounted) {
      _isMergingLatest = false;
      return;
    }
    final viewerId = viewer?.id;
    if (viewerId == null || viewerId.isEmpty) {
      _isMergingLatest = false;
      return;
    }

    try {
      final result = await FeedService.fetchItems(
        viewerId: viewerId,
        status: widget.itemStatus,
        limit: 20,
      );
      if (!mounted) return;
      setState(() {
        final existingIds = _allDocs.map((doc) => doc.id).toSet();
        final newItems = result.items
            .where((doc) => !existingIds.contains(doc.id))
            .toList(growable: false);
        _allDocs.insertAll(0, newItems);
      });
    } catch (error, stackTrace) {
      debugPrint('Feed merge refresh failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      _isMergingLatest = false;
    }
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

  List<FeedItem> _getFilteredAndRankedDocs() {
    final activeDocs = _allDocs.where((doc) => _isItemActive(doc.data, _openedAt)).toList();
    
    final query = _query.trim().toLowerCase();
    var filtered = activeDocs.where((doc) {
      final status = doc.data['status']?.toString();
      return status == widget.itemStatus;
    }).toList();

    if (query.isNotEmpty) {
      filtered = filtered.where((doc) {
        final item = doc.data;
        final searchableText = [item['item_name'], item['item_price'], item['location']]
            .whereType<Object>()
            .map((value) => value.toString().toLowerCase())
            .join(' ');
        return searchableText.contains(query);
      }).toList();
      return filtered;
    }

    return filtered;
  }

  void _scheduleVisibleSeenCheck() {
    _visibilityDebounce?.cancel();
    _visibilityDebounce = Timer(const Duration(milliseconds: 220), _markVisibleItemsSeen);
  }

  void _markVisibleItemsSeen() {
    final viewerId = _viewerId;
    if (viewerId == null || viewerId.isEmpty || !_scrollController.hasClients) return;

    for (final entry in _itemKeys.entries) {
      final itemId = entry.key;
      if (_seenItemIds.contains(itemId) || _pendingSeenItemIds.contains(itemId)) continue;
      if (_isItemCardMostlyVisible(entry.value)) {
        _seenItemIds.add(itemId);
        _pendingSeenItemIds.add(itemId);
      }
    }

    if (_pendingSeenItemIds.isNotEmpty) {
      _seenFlushTimer ??= Timer(const Duration(milliseconds: 800), _flushSeenItems);
    }
  }

  bool _isItemCardMostlyVisible(GlobalKey key) {
    final context = key.currentContext;
    if (context == null) return false;
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.attached || !renderBox.hasSize) return false;
    final top = renderBox.localToGlobal(Offset.zero).dy;
    final height = renderBox.size.height;
    final bottom = top + height;
    final viewportTop = MediaQuery.paddingOf(context).top + 56;
    final viewportBottom = MediaQuery.sizeOf(context).height - 58;
    final visibleHeight = bottom.clamp(viewportTop, viewportBottom) - top.clamp(viewportTop, viewportBottom);
    return visibleHeight > 0 && visibleHeight / height >= 0.35;
  }

  Future<void> _flushSeenItems() async {
    _seenFlushTimer?.cancel();
    _seenFlushTimer = null;
    final viewerId = _viewerId;
    if (viewerId == null || viewerId.isEmpty || _pendingSeenItemIds.isEmpty) return;

    final pending = List<String>.from(_pendingSeenItemIds);
    _pendingSeenItemIds.clear();
    try {
      await FeedService.markItemsSeen(
        viewerId: viewerId,
        viewerType: _viewerType ?? 'anonymous',
        itemIds: pending,
      );
    } catch (error) {
      debugPrint('Seen write failed: $error');
      _pendingSeenItemIds.addAll(pending);
      _seenFlushTimer ??= Timer(const Duration(seconds: 2), _flushSeenItems);
    }
  }

  @override
  Widget build(BuildContext context) {
    final docs = _getFilteredAndRankedDocs();
    _itemKeys.removeWhere((itemId, _) => !docs.any((d) => d.id == itemId));
    final isLivePage = widget.itemStatus == 'live';
    final showInlineLoading =
        _isLoading && UploadStatusManager.current.value == null;
    final bottomSpacerHeight = MediaQuery.viewPaddingOf(context).bottom + 68;

    WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleVisibleSeenCheck());

    return Stack(
      children: [
        RefreshIndicator(
          color: const Color(0xFFFF7801),
          onRefresh: _refreshFeed,
          child: NotificationListener<ScrollEndNotification>(
            onNotification: (_) { _scheduleVisibleSeenCheck(); return false; },
            child: CustomScrollView(
              key: PageStorageKey('seller-feed-scroll-${widget.itemStatus}-${_isGridView ? 'grid' : 'list'}-$_refreshTick'),
              controller: _scrollController,
              cacheExtent: 900,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(child: _FeedHeader(isGridView: _isGridView, isSearchOpen: _isSearchOpen, onToggleGrid: _toggleLayoutMode)),
                if (_allDocs.isEmpty && showInlineLoading)
                  SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: 2, vertical: _isGridView ? 8 : 12),
                    sliver: _isGridView ? const SliverToBoxAdapter(child: _FeedSkeletonGrid()) : SliverList.builder(itemCount: 3, itemBuilder: (c, i) => const ItemCardSkeleton()),
                  )
                else if (docs.isEmpty && !_isLoading)
                  SliverFillRemaining(hasScrollBody: false, child: Center(child: Text(widget.emptyMessage, style: const TextStyle(fontSize: 16, color: Colors.grey))))
                else ...[
                  SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: 2, vertical: _isGridView ? 8 : 12),
                    sliver: _isGridView
                        ? SliverGrid.builder(
                            itemCount: docs.length,
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 4, mainAxisSpacing: 2, childAspectRatio: 0.58),
                            itemBuilder: (context, index) {
                              _maybeLoadMoreFromBuilder(index, docs.length);
                              return _KeepAliveItem(key: _keyForItem(docs[index].id), child: ItemCard(docId: docs[index].id, item: docs[index].data, isCompact: true, isLivePage: isLivePage));
                            },
                          )
                        : SliverList.builder(
                            itemCount: docs.length,
                            itemBuilder: (context, index) {
                              _maybeLoadMoreFromBuilder(index, docs.length);
                              return _KeepAliveItem(key: _keyForItem(docs[index].id), child: ItemCard(docId: docs[index].id, item: docs[index].data, isLivePage: isLivePage));
                            },
                          ),
                  ),
                  if (showInlineLoading && _allDocs.isNotEmpty)
                    const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: CircularProgressIndicator(color: Color(0xFFFF7801))))),
                ],
                if (_hasMore && !_isSearchOpen)
                  SliverToBoxAdapter(
                    child: _LoadMoreTrigger(
                      isLoading: _isLoading,
                      onVisible: _loadMore,
                    ),
                  ),
                SliverToBoxAdapter(child: SizedBox(height: bottomSpacerHeight)),
              ],
            ),
          ),
        ),
        Positioned(top: 10, left: 12, right: 12, child: Align(alignment: Alignment.topRight, child: _FloatingFeedSearchControl(isSearchOpen: _isSearchOpen, searchController: _searchController, searchFocusNode: _searchFocusNode, onOpenSearch: _openSearch, onCloseSearch: _closeSearch, onQueryChanged: _handleSearchChanged))),
        const Positioned(top: 62, left: 0, right: 0, child: Center(child: _UploadStatusBanner())),
      ],
    );
  }

  GlobalKey _keyForItem(String itemId) => _itemKeys.putIfAbsent(itemId, GlobalKey.new);
}

class _LoadMoreTrigger extends StatefulWidget {
  const _LoadMoreTrigger({
    required this.isLoading,
    required this.onVisible,
  });

  final bool isLoading;
  final VoidCallback onVisible;

  @override
  State<_LoadMoreTrigger> createState() => _LoadMoreTriggerState();
}

class _LoadMoreTriggerState extends State<_LoadMoreTrigger> {
  @override
  void initState() {
    super.initState();
    _scheduleLoad();
  }

  @override
  void didUpdateWidget(covariant _LoadMoreTrigger oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleLoad();
  }

  void _scheduleLoad() {
    if (widget.isLoading) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onVisible();
    });
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox(height: 1);
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

class _KeepAliveItem extends StatefulWidget {
  const _KeepAliveItem({super.key, required this.child});

  final Widget child;

  @override
  State<_KeepAliveItem> createState() => _KeepAliveItemState();
}

class _KeepAliveItemState extends State<_KeepAliveItem>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class _FeedHeader extends StatelessWidget {
  const _FeedHeader({
    required this.isGridView,
    required this.isSearchOpen,
    required this.onToggleGrid,
  });

  final bool isGridView;
  final bool isSearchOpen;
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
          if (!isSearchOpen)
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

class _UploadStatusBanner extends StatelessWidget {
  const _UploadStatusBanner();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<UploadStatus?>(
      valueListenable: UploadStatusManager.current,
      builder: (context, status, child) {
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          transitionBuilder: (child, animation) {
            return ScaleTransition(
              scale: CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
              child: FadeTransition(opacity: animation, child: child),
            );
          },
          child: status == null
              ? const SizedBox.shrink()
              : SizedBox(
                  key: ValueKey(status.type),
                  width: 64,
                  height: 64,
                  child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.14),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                    child: Center(
                      child: _UploadStatusIcon(type: status.type),
                    ),
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
        width: 28,
        height: 28,
        child: CircularProgressIndicator(
          strokeWidth: 3,
          color: Color(0xFFFF7801),
        ),
      ),
      UploadStatusType.success => const Icon(
        Icons.check_circle_rounded,
        color: Color(0xFF25D366),
        size: 46,
      ),
      UploadStatusType.error => const Icon(
        Icons.error_rounded,
        color: Colors.red,
        size: 34,
      ),
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

class _FeedViewerIdentity {
  const _FeedViewerIdentity({
    required this.id,
    required this.type,
  });

  final String id;
  final String type;
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
        child: SizedBox(
          width: 44,
          height: 44,
          child: IconButton(
            onPressed: onTap,
            icon: Icon(
              isGridView ? Icons.view_agenda : Icons.grid_view,
            ),
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
