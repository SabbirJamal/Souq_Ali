import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'seller_home_page.dart';
import 'seller_session.dart';
import 'utils/item_status_cache.dart';
import 'utils/network_status.dart';
import 'widgets/app_pull_refresh.dart';
import 'widgets/app_status_bar.dart';
import 'widgets/app_toast.dart';
import 'widgets/item_card.dart';
import 'widgets/media_carousel.dart';
import 'widgets/offline_state.dart';
import 'widgets/seller_bottom_nav_bar.dart';

class SellerProfilePage extends StatelessWidget {
  const SellerProfilePage({
    super.key,
    required this.sellerId,
    required this.sellerPhone,
    required this.fallbackName,
    this.isOwnProfile = true,
  });

  final String sellerId;
  final String sellerPhone;
  final String fallbackName;
  final bool isOwnProfile;

  Future<void> _openHomeTab(BuildContext context, int index) async {
    final session = await SellerSession.current();
    if (!context.mounted) {
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      PageRouteBuilder<void>(
        pageBuilder: (context, animation, secondaryAnimation) =>
            SellerHomePage(
              isSellerMode: session != null,
              initialTabIndex: index,
            ),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
      (route) => false,
    );
  }

  Future<void> _logout(BuildContext context) async {
    await SellerSession.clear();
    if (!context.mounted) {
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      PageRouteBuilder<void>(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const SellerHomePage(isSellerMode: false),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
      (route) => false,
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 36),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 22),
              child: Text(
                'Logout !',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w500),
              ),
            ),
            const Divider(height: 1),
            SizedBox(
              height: 58,
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.black,
                        shape: const RoundedRectangleBorder(),
                      ),
                      child: const Text(
                        'No',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.red,
                        shape: const RoundedRectangleBorder(),
                      ),
                      child: const Text(
                        'Yes',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.red,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (shouldLogout == true && context.mounted) {
      await _logout(context);
    }
  }

  void _openSettings(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
      PageRouteBuilder<void>(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const SellerHomePage(
          isSellerMode: true,
          initialTabIndex: 4,
        ),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusBarHeight = AppStatusBar.heightOf(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.black,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Padding(
              padding: EdgeInsets.only(top: statusBarHeight),
              child: _SellerProfileBody(
                sellerId: sellerId,
                sellerPhone: sellerPhone,
                fallbackName: fallbackName,
                isOwnProfile: isOwnProfile,
                onSettings: () => _openSettings(context),
                onLogout: () => _confirmLogout(context),
                onBack: () => Navigator.pop(context),
              ),
            ),
            const Positioned(top: 0, left: 0, right: 0, child: AppStatusBar()),
          ],
        ),
        bottomNavigationBar: SellerBottomNavBar(
          currentIndex: 4,
          onTap: (index) {
            _openHomeTab(context, index);
          },
        ),
      ),
    );
  }
}

class _SellerProfileBody extends StatefulWidget {
  const _SellerProfileBody({
    required this.sellerId,
    required this.sellerPhone,
    required this.fallbackName,
    required this.isOwnProfile,
    required this.onSettings,
    required this.onLogout,
    required this.onBack,
  });

  final String sellerId;
  final String sellerPhone;
  final String fallbackName;
  final bool isOwnProfile;
  final VoidCallback onSettings;
  final VoidCallback onLogout;
  final VoidCallback? onBack;

  @override
  State<_SellerProfileBody> createState() => _SellerProfileBodyState();
}

class _SellerProfileBodyState extends State<_SellerProfileBody> {
  final _scrollController = ScrollController();
  String get sellerPhone => widget.sellerPhone;
  String get fallbackName => widget.fallbackName;
  bool get isOwnProfile => widget.isOwnProfile;
  VoidCallback get onSettings => widget.onSettings;
  VoidCallback get onLogout => widget.onLogout;
  VoidCallback? get onBack => widget.onBack;
  String _selectedStatus = 'post';

  late final String _sellerDocId =
      widget.sellerId.isNotEmpty ? widget.sellerId : widget.sellerPhone;
  late final Stream<DocumentSnapshot<Map<String, dynamic>>>? _sellerStream =
      _sellerDocId.isEmpty
          ? null
          : FirebaseFirestore.instance
              .collection('sellers')
              .doc(_sellerDocId)
              .snapshots();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels > position.maxScrollExtent - 800) {
      _activePostsKey.currentState?.loadMore();
    }
  }

  final _activePostsKey = GlobalKey<_SellerActivePostsState>();

  Future<void> _refreshPosts() async {
    await _activePostsKey.currentState?.refreshAllStatuses();
  }

  @override
  Widget build(BuildContext context) {
    final sellerDocId = _sellerDocId;
    const headerButtonTop = 7.0;

    return _SellerProfileContentBackground(
      isLive: _selectedStatus == 'live',
      child: Stack(
        children: [
          ColoredBox(
            color: Colors.transparent,
            child: AppPullRefresh(
              onRefresh: _refreshPosts,
              indicatorTop: 132,
              child: CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  if (!isOwnProfile)
                    SliverToBoxAdapter(
                      child: _ProfileScrollableHeader(
                        onBack: onBack,
                        isLive: _selectedStatus == 'live',
                      ),
                    ),
                  SliverToBoxAdapter(
                    child: _SellerProfileTopStream(
                      sellerStream: _sellerStream,
                      fallbackName: fallbackName,
                      sellerPhone: sellerPhone,
                      topPadding: isOwnProfile
                          ? 56 + (MediaQuery.sizeOf(context).height * 0.05)
                          : 16,
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: _ProfileStatusTabs(
                      selectedStatus: _selectedStatus,
                      onChanged: (status) {
                        if (status == _selectedStatus) return;
                        setState(() => _selectedStatus = status);
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (_scrollController.hasClients) {
                            _scrollController.jumpTo(0);
                          }
                        });
                      },
                    ),
                  ),
                  _SellerActivePosts(
                    key: _activePostsKey,
                    sellerId: sellerDocId,
                    selectedStatus: _selectedStatus,
                  ),
                ],
              ),
            ),
          ),
          if (isOwnProfile)
            _ProfileSettingsMenu(onSettings: onSettings, onLogout: onLogout)
          else ...[
            if (onBack != null)
              Positioned(
                top: headerButtonTop,
                left: 14,
                child: _ProfileFloatingBackButton(onBack: onBack!),
              ),
          ],
        ],
      ),
    );
  }
}

class _SellerProfileTopStream extends StatelessWidget {
  const _SellerProfileTopStream({
    required this.sellerStream,
    required this.fallbackName,
    required this.sellerPhone,
    required this.topPadding,
  });

  final Stream<DocumentSnapshot<Map<String, dynamic>>>? sellerStream;
  final String fallbackName;
  final String sellerPhone;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    if (sellerStream == null) {
      return _SellerProfileTop(
        sellerName: fallbackName,
        crNumber: '',
        sellerPhone: sellerPhone,
        topPadding: topPadding,
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: sellerStream,
      builder: (context, sellerSnapshot) {
        final seller = sellerSnapshot.data?.data() ?? {};
        final sellerName =
            seller['name']?.toString().trim().isNotEmpty == true
            ? seller['name'].toString().trim()
            : fallbackName;
        final crNumber =
            seller['cr_number']?.toString().trim().isNotEmpty == true
            ? seller['cr_number'].toString().trim()
            : seller['crNumber']?.toString().trim() ?? '';

        return _SellerProfileTop(
          sellerName: sellerName,
          crNumber: crNumber,
          sellerPhone: sellerPhone,
          topPadding: topPadding,
        );
      },
    );
  }
}

class _ProfileSettingsMenu extends StatelessWidget {
  const _ProfileSettingsMenu({
    required this.onSettings,
    required this.onLogout,
  });

  final VoidCallback onSettings;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    return Positioned(
      top: topInset + 8,
      left: 14,
      child: SafeArea(
        top: false,
        child: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'settings') {
              onSettings();
            } else if (value == 'logout') {
              onLogout();
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'settings', child: Text('Settings')),
            PopupMenuItem(
              value: 'logout',
              child: Text('Log Out', style: TextStyle(color: Colors.red)),
            ),
          ],
          child: Material(
            color: Colors.white,
            shape: const CircleBorder(),
            elevation: 3,
            child: const SizedBox(
              width: 42,
              height: 42,
              child: Icon(Icons.settings, color: Colors.black),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileScrollableHeader extends StatelessWidget {
  const _ProfileScrollableHeader({
    required this.onBack,
    required this.isLive,
  });

  final VoidCallback? onBack;
  final bool isLive;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 50,
          color: isLive ? Colors.transparent : const Color(0xFFF4FBF7),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Stack(
            alignment: Alignment.center,
            children: [
              const SizedBox(
                height: 44,
                width: 152,
                child: Image(
                  image: AssetImage('assets/branding/logo.png'),
                  fit: BoxFit.contain,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileFloatingBackButton extends StatelessWidget {
  const _ProfileFloatingBackButton({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: _BorderedHeaderButton(
        onTap: onBack,
        circular: true,
        borderColor: null,
        child: const Icon(Icons.arrow_back, color: Colors.black),
      ),
    );
  }
}

class _BorderedHeaderButton extends StatelessWidget {
  const _BorderedHeaderButton({
    required this.onTap,
    required this.child,
    this.borderColor = Colors.black,
    this.circular = false,
  });

  final VoidCallback onTap;
  final Widget child;
  final Color? borderColor;
  final bool circular;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(circular ? 999 : 10);
    return Material(
      color: Colors.white,
      borderRadius: borderRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        child: Container(
          width: 44,
          height: circular ? 44 : 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: borderColor == null
                ? null
                : Border.all(color: borderColor!, width: 1.2),
            borderRadius: borderRadius,
          ),
          child: child,
        ),
      ),
    );
  }
}

class _SellerProfileTop extends StatelessWidget {
  const _SellerProfileTop({
    required this.sellerName,
    required this.crNumber,
    required this.sellerPhone,
    required this.topPadding,
  });

  final String sellerName;
  final String crNumber;
  final String sellerPhone;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    final visibleName = sellerName.trim();
    final topLine = [
      if (visibleName.isNotEmpty) visibleName,
      if (crNumber.isNotEmpty) 'CR No. $crNumber',
    ].join(' | ');
    final phoneNumber = _formatSellerPhone(sellerPhone);

    return Container(
      width: double.infinity,
      color: Colors.transparent,
      padding: EdgeInsets.fromLTRB(18, topPadding, 18, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (topLine.isNotEmpty)
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                topLine,
                maxLines: 1,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          if (phoneNumber.isNotEmpty) ...[
            if (topLine.isNotEmpty) const SizedBox(height: 5),
            Text(
              phoneNumber,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _formatSellerPhone(Object? value) {
  final digits = value?.toString().replaceAll(RegExp(r'[^0-9]'), '') ?? '';
  if (digits.isEmpty) {
    return '';
  }
  if (digits.startsWith('968') && digits.length > 3) {
    return '+968 ${digits.substring(3)}';
  }
  return '+968 $digits';
}

class _ProfileStatusTabs extends StatelessWidget {
  const _ProfileStatusTabs({
    required this.selectedStatus,
    required this.onChanged,
  });

  final String selectedStatus;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.transparent,
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.black.withValues(alpha: 0.18)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Expanded(
                child: _ProfileStatusTabButton(
                  text: 'POSTINGS',
                  isSelected: selectedStatus == 'post',
                  selectedColor: const Color(0xFF001341),
                  onTap: () => onChanged('post'),
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(8),
                  ),
                ),
              ),
              Container(width: 1, color: Colors.black.withValues(alpha: 0.18)),
              Expanded(
                child: _ProfileStatusTabButton(
                  text: 'LIVE',
                  isSelected: selectedStatus == 'live',
                  selectedColor: const Color(0xFFFF7801),
                  onTap: () => onChanged('live'),
                  borderRadius: const BorderRadius.horizontal(
                    right: Radius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileStatusTabButton extends StatelessWidget {
  const _ProfileStatusTabButton({
    required this.text,
    required this.isSelected,
    required this.selectedColor,
    required this.onTap,
    required this.borderRadius,
  });

  final String text;
  final bool isSelected;
  final Color selectedColor;
  final VoidCallback onTap;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? selectedColor : Colors.transparent,
      borderRadius: borderRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        child: Center(
          child: Text(
            text,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.black,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ),
      ),
    );
  }
}

class _SellerActivePosts extends StatefulWidget {
  const _SellerActivePosts({
    super.key,
    required this.sellerId,
    required this.selectedStatus,
  });

  final String sellerId;
  final String selectedStatus;

  @override
  State<_SellerActivePosts> createState() => _SellerActivePostsState();
}

class _SellerActivePostsState extends State<_SellerActivePosts> {
  static const _pageSize = 20;

  final ItemStatusCaches _itemCaches = ItemStatusCaches();
  final Set<String> _prefetchedImageUrls = {};
  bool _isOfflinePaginationBlocked = false;
  bool _didShowOfflinePaginationToast = false;
  ItemStatusCache get _activeCache => _itemCaches.forStatus(widget.selectedStatus);
  String get _inactiveStatus => widget.selectedStatus == 'live' ? 'post' : 'live';

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  @override
  void didUpdateWidget(covariant _SellerActivePosts oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sellerId != widget.sellerId) {
      _resetAndLoad();
    } else if (oldWidget.selectedStatus != widget.selectedStatus &&
        _activeCache.docs.isEmpty &&
        !_activeCache.isLoading) {
      _loadInitial();
    }
  }

  Future<void> _resetAndLoad() async {
    setState(() {
      _itemCaches.resetAll();
      _isOfflinePaginationBlocked = false;
      _didShowOfflinePaginationToast = false;
    });
    await _loadInitial();
  }

  Future<void> _loadInitial() => _fetchPageForStatus(widget.selectedStatus, isInitial: true);

  Future<void> loadMore() => _fetchPageForStatus(widget.selectedStatus, isInitial: false);

  Future<void> refreshAllStatuses() async {
    setState(() {
      _itemCaches.resetAll();
      _isOfflinePaginationBlocked = false;
      _didShowOfflinePaginationToast = false;
    });
    await _fetchPageForStatus(widget.selectedStatus, isInitial: true);
    await _fetchPageForStatus(_inactiveStatus, isInitial: true);
  }

  Future<void> retryLoadMore() async {
    if (_activeCache.isLoading) return;
    setState(() {
      _isOfflinePaginationBlocked = false;
    });
    await loadMore();
  }

  Future<void> _fetchPageForStatus(String requestedStatus, {required bool isInitial}) async {
    final cache = _itemCaches.forStatus(requestedStatus);
    if (cache.isLoading ||
        (!isInitial && !cache.hasMore) ||
        (!isInitial && _isOfflinePaginationBlocked) ||
        widget.sellerId.isEmpty) {
      return;
    }

    setState(() {
      cache.isLoading = true;
      if (isInitial) cache.error = null;
    });

    try {
      var query = FirebaseFirestore.instance
          .collection('items')
          .where('seller_uid', isEqualTo: widget.sellerId)
          .where('status', isEqualTo: requestedStatus)
          .orderBy('created_at', descending: true)
          .limit(_pageSize);

      if (!isInitial && cache.lastDoc != null) {
        query = query.startAfterDocument(cache.lastDoc!);
      }

      var snapshot = await query.get();
      if (isInitial &&
          snapshot.docs.isEmpty &&
          requestedStatus == 'post') {
        snapshot = await FirebaseFirestore.instance
            .collection('items')
            .where('seller_uid', isEqualTo: widget.sellerId)
            .orderBy('created_at', descending: true)
            .limit(_pageSize)
            .get();
      }
      if (!mounted) return;

      final now = DateTime.now();
      final activeDocs = snapshot.docs
          .where((doc) =>
              _isItemActive(doc.data(), now) &&
              _matchesQueriedStatus(doc.data(), requestedStatus))
          .toList(growable: false);

      setState(() {
        if (isInitial) cache.reset();
        cache.addUnique(activeDocs);
        cache.lastDoc = snapshot.docs.isEmpty ? cache.lastDoc : snapshot.docs.last;
        cache.hasMore = snapshot.docs.length == _pageSize;
        cache.isLoading = false;
        cache.error = null;
        if (isInitial) {
          _didShowOfflinePaginationToast = false;
        }
        _isOfflinePaginationBlocked = false;
      });
      if (isInitial) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _prefetchProfileThumbnails(cache.docs, isInitial: true);
          }
          if (mounted) {
            _preloadStatusIfNeeded(
              requestedStatus == 'live' ? 'post' : 'live',
            );
          }
        });
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _prefetchProfileThumbnails(activeDocs, isInitial: false);
        });
      }
    } catch (error) {
      if (!mounted) return;
      final isOfflineError = NetworkStatus.isOfflineError(error);
      if (!isInitial &&
          cache.docs.isNotEmpty &&
          isOfflineError &&
          !_didShowOfflinePaginationToast) {
        AppToast.show(context, NetworkStatus.noInternetMessage);
      }
      setState(() {
        cache.error = error;
        cache.isLoading = false;
        if (!isInitial && cache.docs.isNotEmpty && isOfflineError) {
          _isOfflinePaginationBlocked = true;
          _didShowOfflinePaginationToast = true;
        }
      });
    }
  }

  Future<void> _preloadStatusIfNeeded(String status) async {
    final cache = _itemCaches.forStatus(status);
    if (cache.docs.isNotEmpty || cache.isLoading || widget.sellerId.isEmpty) {
      return;
    }
    await _fetchPageForStatus(status, isInitial: true);
  }

  void _prefetchProfileThumbnails(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    required bool isInitial,
  }) {
    final limit = isInitial ? 6 : 4;
    var queued = 0;

    for (var index = 0; index < docs.length && queued < limit; index++) {
      final media = mediaItemsFromMap(docs[index].data());
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
  Widget build(BuildContext context) {
    final cache = _activeCache;
    final docs = cache.docs;
    if (cache.isLoading && docs.isEmpty) {
      return SliverToBoxAdapter(
        child: _SellerProfileContentBackground(
          isLive: widget.selectedStatus == 'live',
          child: const _SellerProfilePostsSkeleton(),
        ),
      );
    }

    if (cache.error != null && docs.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _SellerProfileContentBackground(
          isLive: widget.selectedStatus == 'live',
          child: NetworkStatus.isOfflineError(cache.error!)
              ? OfflineState(onRetry: refreshAllStatuses)
              : Center(child: Text('Error: ${cache.error}')),
        ),
      );
    }

    if (docs.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _SellerProfileContentBackground(
          isLive: widget.selectedStatus == 'live',
          child: const Center(
            child: Text(
              'No active posts',
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
          ),
        ),
      );
    }

    return SliverToBoxAdapter(
      child: _SellerProfileContentBackground(
        isLive: widget.selectedStatus == 'live',
        child: Column(
          children: [
            GridView.builder(
              padding: const EdgeInsets.fromLTRB(2, 4, 2, 12),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: docs.length,
              addAutomaticKeepAlives: false,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 4,
                mainAxisSpacing: 2,
                childAspectRatio: 0.58,
              ),
              itemBuilder: (context, index) {
                final doc = docs[index];
                return ItemCard(
                  key: ValueKey(doc.id),
                  docId: doc.id,
                  item: doc.data(),
                  isCompact: true,
                  isLivePage: widget.selectedStatus == 'live',
                  replaceOnOpen: true,
                );
              },
            ),
            if (_isOfflinePaginationBlocked &&
                docs.isNotEmpty &&
                NetworkStatus.isOfflineError(cache.error ?? ''))
              _SellerProfileOfflineLoadMore(onRetry: retryLoadMore)
            else if (cache.isLoading)
              const _SellerProfilePostsSkeleton(),
          ],
        ),
      ),
    );
  }
}

class _SellerProfileContentBackground extends StatelessWidget {
  const _SellerProfileContentBackground({
    required this.isLive,
    required this.child,
  });

  final bool isLive;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isLive ? null : const Color(0xFFF4FBF7),
        gradient: isLive
            ? const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFFFE9EC), Color(0xFFF4FBF7)],
              )
            : null,
      ),
      child: child,
    );
  }
}

class _SellerProfilePostsSkeleton extends StatelessWidget {
  const _SellerProfilePostsSkeleton();

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 12),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 2,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 4,
        mainAxisSpacing: 2,
        childAspectRatio: 0.58,
      ),
      itemBuilder: (context, index) => const ItemCardSkeleton(isCompact: true),
    );
  }
}

class _SellerProfileOfflineLoadMore extends StatelessWidget {
  const _SellerProfileOfflineLoadMore({required this.onRetry});

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

bool _matchesQueriedStatus(Map<String, dynamic> item, String selectedStatus) {
  final status = item['status']?.toString().trim().toLowerCase();
  if (selectedStatus == 'live') return status == 'live';
  return status == null || status.isEmpty || status == 'post';
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
