import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/feed_service.dart';
import '../seller_session.dart';
import '../upload_status_manager.dart';
import '../utils/network_status.dart';
import '../widgets/app_pull_refresh.dart';
import '../widgets/app_toast.dart';
import '../widgets/item_card.dart';
import '../widgets/media_carousel.dart';
import '../widgets/offline_state.dart';

class SellerFeedTab extends StatefulWidget {
  const SellerFeedTab({
    super.key,
    this.chromeVisibleListenable,
    this.activeTabListenable,
    this.tabIndex = 0,
    this.gridLayoutMode,
    required this.onSearchActiveChanged,
    this.itemStatus = 'post',
    this.emptyMessage = 'No items available',
  });

  final ValueListenable<bool>? chromeVisibleListenable;
  final ValueListenable<int>? activeTabListenable;
  final int tabIndex;
  final ValueNotifier<bool>? gridLayoutMode;
  final ValueChanged<bool> onSearchActiveChanged;
  final String itemStatus;
  final String emptyMessage;

  @override
  SellerFeedTabState createState() => SellerFeedTabState();
}

class SellerFeedTabState extends State<SellerFeedTab> {
  static const _initialFetchLimit = 16;
  static const _nextFetchLimit = 32;
  static const _mergeLatestLimit = 20;
  static const _visibilityCheckDelay = Duration(milliseconds: 320);

  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _scrollController = ScrollController();
  final Map<String, GlobalKey> _itemKeys = {};
  final Set<String> _seenItemIds = {};
  final Set<String> _pendingSeenItemIds = {};
  final Set<String> _prefetchedImageUrls = {};

  final List<FeedItem> _allDocs = [];
  List<FeedItem>? _cachedFilteredDocs;
  String? _cachedQueryForFilter;
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
  Object? _loadError;
  final DateTime _openedAt = DateTime.now();
  int _refreshTick = 0;

  @override
  void initState() {
    super.initState();
    _isGridView = widget.gridLayoutMode?.value ?? _isGridView;
    widget.gridLayoutMode?.addListener(_handleGridLayoutModeChanged);
    widget.activeTabListenable?.addListener(_handleActiveTabChanged);
    _scrollController.addListener(_onScroll);
    _loadInitial();
  }

  @override
  void didUpdateWidget(covariant SellerFeedTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gridLayoutMode != widget.gridLayoutMode) {
      oldWidget.gridLayoutMode?.removeListener(_handleGridLayoutModeChanged);
      _isGridView = widget.gridLayoutMode?.value ?? _isGridView;
      widget.gridLayoutMode?.addListener(_handleGridLayoutModeChanged);
    }
    if (oldWidget.activeTabListenable != widget.activeTabListenable) {
      oldWidget.activeTabListenable?.removeListener(_handleActiveTabChanged);
      widget.activeTabListenable?.addListener(_handleActiveTabChanged);
    }
  }

  void _onScroll() {
    _scheduleVisibleSeenCheck();
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
    if (!_scrollController.hasClients ||
        _scrollController.position.pixels <= 80 ||
        total - index > 12 ||
        _isLoading ||
        !_hasMore ||
        _isSearchOpen) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadMore();
    });
  }

  Future<void> _fetchPage({
    required bool isInitial,
    bool useWarmup = true,
  }) async {
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

      final requestedLimit = isInitial ? _initialFetchLimit : _nextFetchLimit;
      final result = await FeedService.fetchItems(
        viewerId: viewerId,
        status: widget.itemStatus,
        cursor: isInitial ? null : _feedCursor,
        limit: requestedLimit,
        useWarmup: useWarmup,
      );
      if (!mounted) return;
      setState(() {
        if (isInitial) {
          _allDocs.clear();
        }
        final existingIds = _allDocs.map((doc) => doc.id).toSet();
        _allDocs.addAll(result.items.where((doc) => !existingIds.contains(doc.id)));
        _feedCursor = result.cursor;
        _hasMore = result.hasMore || result.items.length >= requestedLimit;
        _isLoading = false;
        _cachedFilteredDocs = null;
        _loadError = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _prefetchFeedThumbnails(result.items, isInitial: isInitial);
      });
      _scheduleVisibleSeenCheck();
    } catch (error, stackTrace) {
      debugPrint('Feed load failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      if (_allDocs.isNotEmpty && NetworkStatus.isOfflineError(error)) {
        AppToast.show(context, NetworkStatus.noInternetMessage);
      }
      setState(() {
        _loadError = error;
        _isLoading = false;
      });
    }
  }

  void _prefetchFeedThumbnails(
    List<FeedItem> items, {
    required bool isInitial,
  }) {
    final limit = isInitial ? 6 : 4;
    var queued = 0;

    for (var index = 0; index < items.length && queued < limit; index++) {
      final media = mediaItemsFromMap(items[index].data);
      if (media.isEmpty) continue;

      final first = media.first;
      final thumbnailUrl = first.thumbnailUrl?.trim() ?? '';
      final fallbackUrl = first.url.trim();
      final url = thumbnailUrl.isNotEmpty
          ? thumbnailUrl
          : (!first.isVideo && index < 4 ? fallbackUrl : '');
      if (url.isEmpty || !_prefetchedImageUrls.add(url)) continue;

      queued += 1;
      precacheImage(
        CachedNetworkImageProvider(url, maxWidth: 500),
        context,
      ).catchError((_) {});
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    widget.gridLayoutMode?.removeListener(_handleGridLayoutModeChanged);
    widget.activeTabListenable?.removeListener(_handleActiveTabChanged);
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

  void _handleGridLayoutModeChanged() {
    final nextValue = widget.gridLayoutMode?.value;
    if (nextValue == null || nextValue == _isGridView || !mounted) {
      return;
    }
    if (_isActiveTab) {
      setState(() => _isGridView = nextValue);
    } else {
      _isGridView = nextValue;
    }
  }

  void _handleActiveTabChanged() {
    if (!mounted) return;
    if (!_isActiveTab) {
      if (_isSearchOpen) _closeSearch();
      return;
    }
    final nextValue = widget.gridLayoutMode?.value;
    if (nextValue == null || nextValue == _isGridView) return;
    setState(() => _isGridView = nextValue);
  }

  bool get _isActiveTab =>
      widget.activeTabListenable == null ||
      widget.activeTabListenable!.value == widget.tabIndex;

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
        setState(() {
          _query = value;
          _cachedFilteredDocs = null;
        });
      }
    });
  }

  void scrollToTop() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(0, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
  }

  Future<void> scrollToTopOrRefresh() async {
    if (!_scrollController.hasClients || _scrollController.offset <= 8) {
      await reloadItems();
      return;
    }
    scrollToTop();
  }

  Future<void> _refreshFeed() async {
    _markVisibleItemsSeen();
    await _flushSeenItems();
    setState(() {
      _refreshTick++;
      _allDocs.clear();
      _hasMore = true;
      _feedCursor = null;
      _cachedFilteredDocs = null;
    });
    await _fetchPage(isInitial: true);
  }

  Future<void> reloadItems({bool forceFresh = false}) async {
    _markVisibleItemsSeen();
    await _flushSeenItems();
    setState(() {
      _refreshTick++;
      _allDocs.clear();
      _hasMore = true;
      _feedCursor = null;
      _cachedFilteredDocs = null;
    });
    await _fetchPage(isInitial: true, useWarmup: !forceFresh);
  }

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
        limit: _mergeLatestLimit,
      );
      if (!mounted) return;
      setState(() {
        final existingIds = _allDocs.map((doc) => doc.id).toSet();
        final newItems = result.items
            .where((doc) => !existingIds.contains(doc.id))
            .toList(growable: false);
        _allDocs.insertAll(0, newItems);
        _cachedFilteredDocs = null;
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
    final nextValue = !_isGridView;
    final sharedMode = widget.gridLayoutMode;
    if (sharedMode != null) {
      setState(() => _isGridView = nextValue);
      sharedMode.value = nextValue;
    } else {
      setState(() => _isGridView = nextValue);
    }
  }

  List<FeedItem> _getFilteredAndRankedDocs() {
    final query = _query.trim().toLowerCase();
    if (_cachedFilteredDocs != null && _cachedQueryForFilter == query) {
      return _cachedFilteredDocs!;
    }

    final activeDocs = _allDocs.where((doc) => _isItemActive(doc.data, _openedAt)).toList();
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
    }

    _cachedFilteredDocs = filtered;
    _cachedQueryForFilter = query;
    return filtered;
  }

  void _scheduleVisibleSeenCheck() {
    _visibilityDebounce?.cancel();
    _visibilityDebounce = Timer(_visibilityCheckDelay, _markVisibleItemsSeen);
  }

  void _markVisibleItemsSeen() {
    final viewerId = _viewerId;
    if (viewerId == null ||
        viewerId.isEmpty ||
        _itemKeys.isEmpty ||
        !_scrollController.hasClients ||
        !mounted) {
      return;
    }

    final viewportTop = MediaQuery.paddingOf(context).top + 56;
    final viewportBottom = MediaQuery.sizeOf(context).height - 58;

    for (final entry in _itemKeys.entries) {
      final itemId = entry.key;
      if (_seenItemIds.contains(itemId) || _pendingSeenItemIds.contains(itemId)) continue;
      if (_isItemCardMostlyVisible(entry.value, viewportTop, viewportBottom)) {
        _seenItemIds.add(itemId);
        _pendingSeenItemIds.add(itemId);
      }
    }

    if (_pendingSeenItemIds.isNotEmpty) {
      _seenFlushTimer ??= Timer(const Duration(milliseconds: 800), _flushSeenItems);
    }
  }

  bool _isItemCardMostlyVisible(GlobalKey key, double viewportTop, double viewportBottom) {
    final context = key.currentContext;
    if (context == null) return false;
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.attached || !renderBox.hasSize) return false;
    final top = renderBox.localToGlobal(Offset.zero).dy;
    final height = renderBox.size.height;
    final bottom = top + height;
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
    final docIds = docs.map((doc) => doc.id).toSet();
    _itemKeys.removeWhere((itemId, _) => !docIds.contains(itemId));
    final isLivePage = widget.itemStatus == 'live';
    final showInlineLoading =
        _isLoading && UploadStatusManager.current.value == null;
    final bottomSpacerHeight = MediaQuery.viewPaddingOf(context).bottom + 90;

    final content = Stack(
      children: [
        AppPullRefresh(
          onRefresh: _refreshFeed,
          indicatorTop: 96,
          child: NotificationListener<ScrollEndNotification>(
            onNotification: (_) { _scheduleVisibleSeenCheck(); return false; },
            child: CustomScrollView(
              key: PageStorageKey('seller-feed-scroll-${widget.itemStatus}-$_refreshTick'),
              controller: _scrollController,
              cacheExtent: 900,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                      SliverToBoxAdapter(child: _FeedHeader(isGridView: _isGridView, isSearchOpen: _isSearchOpen, onToggleGrid: _toggleLayoutMode)),
                      if (_allDocs.isEmpty && showInlineLoading)
                        SliverPadding(
                          padding: EdgeInsets.symmetric(horizontal: 2, vertical: _isGridView ? 8 : 12),
                          sliver: _isGridView
                              ? SliverGrid.builder(
                                  itemCount: 6,
                                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 4, mainAxisSpacing: 2, childAspectRatio: 0.58),
                                  itemBuilder: (context, index) => const _SkeletonFeedItemCard(isCompact: true),
                                )
                              : SliverList.builder(itemCount: 3, itemBuilder: (context, index) => const _SkeletonFeedItemCard()),
                        )
                      else if (docs.isEmpty && !_isLoading)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: NetworkStatus.isOfflineError(_loadError ?? '')
                              ? OfflineState(onRetry: _refreshFeed)
                              : Center(child: Text(widget.emptyMessage, style: const TextStyle(fontSize: 16, color: Colors.grey))),
                        )
                      else ...[
                        SliverPadding(
                          padding: EdgeInsets.symmetric(horizontal: 2, vertical: _isGridView ? 8 : 12),
                          sliver: _isGridView
                              ? SliverGrid.builder(
                                  itemCount: docs.length,
                                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 4, mainAxisSpacing: 2, childAspectRatio: 0.58),
                                  itemBuilder: (context, index) {
                                    _maybeLoadMoreFromBuilder(index, docs.length);
                                    return ItemCard(key: _keyForItem(docs[index].id), docId: docs[index].id, item: docs[index].data, isCompact: true, isLivePage: isLivePage);
                                  },
                                )
                              : SliverList.builder(
                                  itemCount: docs.length,
                                  itemBuilder: (context, index) {
                                    _maybeLoadMoreFromBuilder(index, docs.length);
                                    return ItemCard(key: _keyForItem(docs[index].id), docId: docs[index].id, item: docs[index].data, isLivePage: isLivePage);
                                  },
                                ),
                        ),
                        if (showInlineLoading && _allDocs.isNotEmpty)
                          SliverPadding(
                            padding: EdgeInsets.symmetric(horizontal: 2, vertical: _isGridView ? 8 : 12),
                            sliver: _isGridView
                                ? SliverGrid.builder(
                                    itemCount: 4,
                                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 4, mainAxisSpacing: 2, childAspectRatio: 0.58),
                                    itemBuilder: (context, index) => const _SkeletonFeedItemCard(isCompact: true),
                                  )
                                : SliverList.builder(itemCount: 2, itemBuilder: (context, index) => const _SkeletonFeedItemCard()),
                          ),
                      ],
                      SliverToBoxAdapter(child: SizedBox(height: bottomSpacerHeight)),
                    ],
                  ),
                ),
        ),
        Positioned(top: 10, left: 12, right: 12, child: Align(alignment: Alignment.topRight, child: _FloatingFeedSearchControl(isSearchOpen: _isSearchOpen, searchController: _searchController, searchFocusNode: _searchFocusNode, onOpenSearch: _openSearch, onCloseSearch: _closeSearch, onQueryChanged: _handleSearchChanged))),
      ],
    );
    if (!isLivePage) return content;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFE9EC), Color(0xFFF4FBF7)],
        ),
      ),
      child: content,
    );
  }

  GlobalKey _keyForItem(String itemId) => _itemKeys.putIfAbsent(itemId, GlobalKey.new);
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

class _SkeletonFeedItemCard extends StatelessWidget {
  const _SkeletonFeedItemCard({
    this.isCompact = false,
  });

  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    return ItemCardSkeleton(isCompact: isCompact);
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
