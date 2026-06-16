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
    required this.onSearchActiveChanged,
    this.itemStatus = 'post',
    this.emptyMessage = 'No items available',
  });

  final ValueListenable<bool>? chromeVisibleListenable;
  final ValueListenable<int>? activeTabListenable;
  final int tabIndex;
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
  bool _isSearchOpen = false;
  bool _isLoading = false;
  bool _isMergingLatest = false;
  bool _isOfflinePaginationBlocked = false;
  bool _didShowOfflinePaginationToast = false;
  bool _hasMore = true;
  String _query = '';
  Timer? _searchDebounce;
  Timer? _searchFocusTimer;
  Timer? _visibilityDebounce;
  Timer? _seenFlushTimer;
  Future<void>? _activeRefreshFuture;
  String? _viewerId;
  String? _viewerType;
  FeedCursor? _feedCursor;
  Object? _loadError;
  final DateTime _openedAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    widget.activeTabListenable?.addListener(_handleActiveTabChanged);
    _scrollController.addListener(_onScroll);
    _loadInitial();
  }

  @override
  void didUpdateWidget(covariant SellerFeedTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeTabListenable != widget.activeTabListenable) {
      oldWidget.activeTabListenable?.removeListener(_handleActiveTabChanged);
      widget.activeTabListenable?.addListener(_handleActiveTabChanged);
    }
  }

  void _onScroll() {
    _scheduleVisibleSeenCheck();
    if (!_scrollController.hasClients ||
        _isLoading ||
        !_hasMore ||
        _isOfflinePaginationBlocked) {
      return;
    }
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
        _isOfflinePaginationBlocked ||
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
        if (isInitial) {
          _didShowOfflinePaginationToast = false;
        }
        _isOfflinePaginationBlocked = false;
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
      final isOfflineError = NetworkStatus.isOfflineError(error);
      if (!isInitial &&
          _allDocs.isNotEmpty &&
          isOfflineError &&
          !_didShowOfflinePaginationToast) {
        AppToast.show(context, NetworkStatus.noInternetMessage);
      }
      setState(() {
        _loadError = error;
        _isLoading = false;
        if (!isInitial && _allDocs.isNotEmpty && isOfflineError) {
          _isOfflinePaginationBlocked = true;
          _didShowOfflinePaginationToast = true;
        }
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
    widget.activeTabListenable?.removeListener(_handleActiveTabChanged);
    widget.onSearchActiveChanged(false);
    _searchDebounce?.cancel();
    _searchFocusTimer?.cancel();
    _visibilityDebounce?.cancel();
    _seenFlushTimer?.cancel();
    _flushSeenItems();
    _scrollController.dispose();
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _handleActiveTabChanged() {
    if (!mounted) return;
    if (!_isActiveTab) {
      if (_isSearchOpen) _closeSearch();
    }
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
    if (_activeRefreshFuture != null) return _activeRefreshFuture!;
    final future = _performRefresh(useWarmup: false);
    _activeRefreshFuture = future;
    try {
      await future;
    } finally {
      if (identical(_activeRefreshFuture, future)) {
        _activeRefreshFuture = null;
      }
    }
  }

  Future<void> _performRefresh({required bool useWarmup}) async {
    _markVisibleItemsSeen();
    await _flushSeenItems();
    setState(() {
      _allDocs.clear();
      _hasMore = true;
      _feedCursor = null;
      _cachedFilteredDocs = null;
      _loadError = null;
      _isOfflinePaginationBlocked = false;
      _didShowOfflinePaginationToast = false;
    });
    await _fetchPage(isInitial: true, useWarmup: useWarmup);
  }

  Future<void> reloadItems({bool forceFresh = false}) async {
    if (_activeRefreshFuture != null) return _activeRefreshFuture!;
    final future = _performRefresh(useWarmup: !forceFresh);
    _activeRefreshFuture = future;
    try {
      await future;
    } finally {
      if (identical(_activeRefreshFuture, future)) {
        _activeRefreshFuture = null;
      }
    }
  }

  Future<void> _retryLoadMore() async {
    if (_isLoading) return;
    setState(() {
      _loadError = null;
      _isOfflinePaginationBlocked = false;
    });
    await _loadMore();
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
    if (_isSearchOpen) return;
    setState(() => _isSearchOpen = true);
    widget.onSearchActiveChanged(true);
    _searchFocusTimer?.cancel();
    _searchFocusTimer = Timer(const Duration(milliseconds: 220), () {
      if (mounted && _isSearchOpen) {
        _searchFocusNode.requestFocus();
      }
    });
  }

  void _closeSearch() {
    _searchFocusTimer?.cancel();
    _searchFocusNode.unfocus();
    _searchController.clear();
    widget.onSearchActiveChanged(false);
    setState(() {
      _isSearchOpen = false;
      _query = '';
    });
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
              key: PageStorageKey('seller-feed-scroll-${widget.itemStatus}'),
              controller: _scrollController,
              cacheExtent: 900,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                      SliverToBoxAdapter(child: _FeedHeader(isSearchOpen: _isSearchOpen)),
                      if (_allDocs.isEmpty && showInlineLoading)
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
                          sliver: SliverGrid.builder(
                            itemCount: 6,
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 4, mainAxisSpacing: 2, childAspectRatio: 0.58),
                            itemBuilder: (context, index) => const _SkeletonFeedItemCard(isCompact: true),
                          ),
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
                          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
                          sliver: SliverGrid.builder(
                            itemCount: docs.length,
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 4, mainAxisSpacing: 2, childAspectRatio: 0.58),
                            itemBuilder: (context, index) {
                              _maybeLoadMoreFromBuilder(index, docs.length);
                              return ItemCard(key: _keyForItem(docs[index].id), docId: docs[index].id, item: docs[index].data, isCompact: true, isLivePage: isLivePage);
                            },
                          ),
                        ),
                        if (_isOfflinePaginationBlocked &&
                            _allDocs.isNotEmpty &&
                            NetworkStatus.isOfflineError(_loadError ?? ''))
                          SliverToBoxAdapter(
                            child: _FeedOfflineLoadMore(
                              onRetry: _retryLoadMore,
                            ),
                          )
                        else if (showInlineLoading && _allDocs.isNotEmpty)
                          SliverPadding(
                            padding: EdgeInsets.fromLTRB(
                              2,
                              0,
                              2,
                              8,
                            ),
                            sliver: SliverGrid.builder(
                              itemCount: 4,
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 4, mainAxisSpacing: 2, childAspectRatio: 0.58),
                              itemBuilder: (context, index) => const _SkeletonFeedItemCard(isCompact: true),
                            ),
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final showSearchField =
                isSearchOpen && constraints.maxWidth > 140;
            return Stack(
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: !showSearchField,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 140),
                      opacity: showSearchField ? 1 : 0,
                      child: Row(
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
                              focusNode: searchFocusNode,
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
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: isSearchOpen,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 120),
                      opacity: isSearchOpen ? 0 : 1,
                      child: Align(
                        alignment: Alignment.center,
                        child: IconButton(
                          onPressed: onOpenSearch,
                          icon: const Icon(Icons.search),
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _FeedHeader extends StatelessWidget {
  const _FeedHeader({
    required this.isSearchOpen,
  });

  final bool isSearchOpen;

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

class _FeedOfflineLoadMore extends StatelessWidget {
  const _FeedOfflineLoadMore({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.wifi_off_rounded,
            size: 34,
            color: Color(0xFF9A9A9A),
          ),
          const SizedBox(height: 10),
          const Text(
            'No internet connection',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Color(0xFF777777),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 38,
            child: ElevatedButton(
              onPressed: () => onRetry(),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF7801),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 22),
              ),
              child: const Text(
                'Retry',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
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
