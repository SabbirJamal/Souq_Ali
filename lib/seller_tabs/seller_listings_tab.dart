import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../item_edit_page.dart';
import '../seller_session.dart';
import '../seller_session_guard.dart';
import '../utils/formatters.dart';
import '../utils/item_status_cache.dart';
import '../utils/network_status.dart';
import '../utils/price_input.dart';
import '../widgets/app_toast.dart';
import '../widgets/app_pull_refresh.dart';
import '../widgets/item_card.dart';
import '../widgets/media_carousel.dart';
import '../widgets/offline_state.dart';
import '../widgets/price_with_currency.dart';
import '../widgets/responsive_text.dart';

class SellerListingsTab extends StatefulWidget {
  const SellerListingsTab({
    super.key,
    this.refreshTick = 0,
    this.initialStatus = 'post',
    this.onReady,
    this.onSessionInvalid,
  });

  final int refreshTick;
  final String initialStatus;
  final ValueChanged<SellerListingsTabState>? onReady;
  final VoidCallback? onSessionInvalid;

  @override
  SellerListingsTabState createState() => SellerListingsTabState();
}

class SellerListingsTabState extends State<SellerListingsTab> {
  static const _pageSize = 15;
  static const _priceUnits = ['/ kg', '/ ton', '/ box', '/ bag'];

  late final Future<SellerSession?> _sessionFuture;
  final ValueNotifier<DateTime> _nowNotifier = ValueNotifier(DateTime.now());
  final _scrollController = ScrollController();
  final ItemStatusCaches _itemCaches = ItemStatusCaches();
  final Set<String> _prefetchedImageUrls = {};
  late String _selectedStatus = widget.initialStatus == 'live' ? 'live' : 'post';
  ItemStatusCache get _activeCache => _itemCaches.forStatus(_selectedStatus);

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _sessionFuture = SellerSession.current();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onReady?.call(this);
    });
    _loadInitial();
  }

  void _onScroll() {
    final cache = _activeCache;
    if (!_scrollController.hasClients || cache.isLoading || !cache.hasMore) return;
    if (_scrollController.position.pixels > _scrollController.position.maxScrollExtent - 800) {
      _loadMore();
    }
  }

  Future<void> _loadInitial() async {
    final session = await _sessionFuture;
    if (session == null) return;
    await _fetchPageForStatus(session, _selectedStatus, isInitial: true);
  }

  Future<void> reloadItems() async {
    _nowNotifier.value = DateTime.now();
    if (mounted) {
      setState(() {
        _itemCaches.resetStatus(_selectedStatus);
      });
    }
    await _loadInitial();
  }

  Future<void> scrollToTopOrRefresh() async {
    if (!_scrollController.hasClients || _scrollController.offset <= 8) {
      await reloadItems();
      return;
    }
    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _loadMore() async {
    final session = await _sessionFuture;
    if (session == null) return;
    await _fetchPageForStatus(session, _selectedStatus, isInitial: false);
  }

  Future<void> _fetchPageForStatus(
    SellerSession session,
    String requestedStatus, {
    required bool isInitial,
  }) async {
    final cache = _itemCaches.forStatus(requestedStatus);
    if (cache.isLoading || (!isInitial && !cache.hasMore)) return;
    setState(() => cache.isLoading = true);

    try {
      var query = FirebaseFirestore.instance
          .collection('items')
          .where('seller_uid', isEqualTo: session.sellerId)
          .limit(_pageSize * 4);

      final snapshot = await query.get();
      if (!mounted) return;

      var newDocs = _sortedByCreatedAtDesc(snapshot.docs);
      if (newDocs.isEmpty && isInitial) {
        final legacySnapshot = await FirebaseFirestore.instance
            .collection('items')
            .where('seller_phone', isEqualTo: session.phoneNumber)
            .limit(_pageSize * 4)
            .get();
        newDocs = _sortedByCreatedAtDesc(legacySnapshot.docs);
      }
      setState(() {
        if (isInitial) cache.reset();
        cache.addUnique(
          newDocs.where((doc) => _matchesStatus(doc.data(), requestedStatus)),
        );
        cache.hasMore = false;
        if (isInitial) cache.hasLoadedInitial = true;
        cache.isLoading = false;
        cache.error = null;
      });
      final matchingDocs = newDocs
          .where((doc) => _matchesStatus(doc.data(), requestedStatus))
          .toList(growable: false);
      if (isInitial) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _prefetchListingThumbnails(cache.docs, isInitial: true);
          if (mounted) {
            _preloadStatusIfNeeded(session, requestedStatus == 'live' ? 'post' : 'live');
          }
        });
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _prefetchListingThumbnails(matchingDocs, isInitial: false);
        });
      }
    } catch (e) {
      try {
        var fallbackQuery = FirebaseFirestore.instance
            .collection('items')
            .where('seller_uid', isEqualTo: session.sellerId)
            .limit(_pageSize * 4);

        final snapshot = await fallbackQuery.get();
        if (!mounted) return;
        var newDocs = _sortedByCreatedAtDesc(snapshot.docs);
        if (newDocs.isEmpty && isInitial) {
          final legacySnapshot = await FirebaseFirestore.instance
              .collection('items')
              .where('seller_phone', isEqualTo: session.phoneNumber)
              .limit(_pageSize * 4)
              .get();
          newDocs = _sortedByCreatedAtDesc(legacySnapshot.docs);
        }
        setState(() {
          if (isInitial) cache.reset();
          cache.addUnique(
            newDocs.where((doc) => _matchesStatus(doc.data(), requestedStatus)),
          );
          cache.hasMore = false;
          if (isInitial) cache.hasLoadedInitial = true;
          cache.isLoading = false;
          cache.error = null;
        });
        final matchingDocs = newDocs
            .where((doc) => _matchesStatus(doc.data(), requestedStatus))
            .toList(growable: false);
        if (isInitial) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _prefetchListingThumbnails(cache.docs, isInitial: true);
            if (mounted) {
              _preloadStatusIfNeeded(session, requestedStatus == 'live' ? 'post' : 'live');
            }
          });
        } else {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _prefetchListingThumbnails(matchingDocs, isInitial: false);
          });
        }
      } catch (_) {
        if (!mounted) return;
        if (cache.docs.isNotEmpty && NetworkStatus.isOfflineError(e)) {
          AppToast.show(context, NetworkStatus.noInternetMessage);
        }
        setState(() {
          cache.error = e;
          cache.isLoading = false;
        });
      }
    }
  }

  Future<void> _preloadStatusIfNeeded(
    SellerSession session,
    String status,
  ) async {
    final cache = _itemCaches.forStatus(status);
    if (cache.hasLoadedInitial || cache.isLoading) return;
    await _fetchPageForStatus(session, status, isInitial: true);
  }

  void _prefetchListingThumbnails(
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

  // Precompute sort keys once instead of converting Timestamps per comparison.
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _sortedByCreatedAtDesc(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final keyed = [
      for (final doc in docs)
        MapEntry(_createdAt(doc.data()) ?? DateTime.fromMillisecondsSinceEpoch(0), doc),
    ]..sort((a, b) => b.key.compareTo(a.key));
    return [for (final entry in keyed) entry.value];
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _nowNotifier.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SellerListingsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshTick != oldWidget.refreshTick) {
      _nowNotifier.value = DateTime.now();
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
      _itemCaches.resetStatus(_selectedStatus);
      _loadInitial();
    }
  }

  DateTime? _createdAt(Map<String, dynamic> item) {
    final createdAt = item['created_at'];
    if (createdAt is Timestamp) return createdAt.toDate();
    if (createdAt is DateTime) return createdAt;
    return null;
  }

  DateTime? _expiryAt(Map<String, dynamic> item) {
    final expiresAt = item['expires_at'];
    if (expiresAt is Timestamp) return expiresAt.toDate();
    if (expiresAt is DateTime) return expiresAt;

    final postedAt = _createdAt(item);
    final timePeriodHours = item['time_period_hours'];
    if (postedAt == null || timePeriodHours is! num) return null;
    return postedAt.add(Duration(hours: timePeriodHours.toInt()));
  }

  bool _isItemActive(Map<String, dynamic> item, DateTime now) {
    final expiryAt = _expiryAt(item);
    return expiryAt == null || expiryAt.isAfter(now);
  }

  bool _matchesSelectedStatus(Map<String, dynamic> item) {
    return _matchesStatus(item, _selectedStatus);
  }

  bool _matchesStatus(Map<String, dynamic> item, String statusFilter) {
    final status = item['status']?.toString();
    if (statusFilter == 'post') return status == null || status.isEmpty || status == 'post';
    return status == statusFilter;
  }

  String _uploadedAgo(Object? value, DateTime now) {
    DateTime? uploadedAt;
    if (value is Timestamp) {
      uploadedAt = value.toDate();
    } else if (value is DateTime) {
      uploadedAt = value;
    }
    if (uploadedAt == null) return 'just now';

    final difference = now.difference(uploadedAt);
    if (difference.inMinutes < 1) return 'just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes} min ago';
    if (difference.inHours < 24) return '${difference.inHours} hrs ago';
    if (difference.inDays < 7) return '${difference.inDays} days ago';
    return '${difference.inDays ~/ 7} weeks ago';
  }

  String _expiryText(Map<String, dynamic> item, DateTime now) {
    final expiryAt = _expiryAt(item);
    if (expiryAt == null) return 'Exp not set';
    final remaining = expiryAt.difference(now);
    if (remaining <= Duration.zero) return 'Expired';

    final minutes = (remaining.inSeconds / 60).ceil();
    if (minutes < 60) return 'Exp. $minutes ${minutes == 1 ? 'Min' : 'Mins'}';

    final hours = minutes ~/ 60;
    final extraMinutes = minutes % 60;
    if (extraMinutes == 0) return 'Exp. $hours ${hours == 1 ? 'Hr' : 'Hrs'}';
    return 'Exp. $hours ${hours == 1 ? 'Hr' : 'Hrs'} $extraMinutes Mins';
  }

  String _renewPriceText(Map<String, dynamic> item) {
    final priceNumber = item['price_number']?.toString().trim() ?? '';
    if (priceNumber.isNotEmpty) return priceNumber.replaceAll(',', '');
    final priceText = item['item_price']?.toString() ?? '';
    return RegExp(r'\d+(?:[\.,]\d+)?').firstMatch(priceText)?.group(0)?.replaceAll(',', '') ?? '';
  }

  String _renewPriceUnit(Map<String, dynamic> item) {
    final unit = item['price_unit']?.toString().trim() ?? '';
    if (_priceUnits.contains(unit)) return unit;
    final priceText = item['item_price']?.toString() ?? '';
    for (final option in _priceUnits) { if (priceText.contains(option)) return option; }
    return _priceUnits.first;
  }

  String? _normalizeRenewPrice(String value) {
    return normalizePriceInput(value);
  }

  String _formatRenewPrice(String value) {
    final parts = value.split('.');
    final whole = parts.first;
    final buffer = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      final remaining = whole.length - i;
      buffer.write(whole[i]);
      if (remaining > 1 && remaining % 3 == 1) buffer.write(',');
    }
    return '${buffer.toString()}.${parts.length > 1 ? parts.last : '000'}';
  }

  Future<void> _deleteItem(BuildContext context, String docId) async {
    if (!await SellerSessionGuard.ensureActive(context, onInvalid: widget.onSessionInvalid ?? () {})) return;
    if (!await NetworkStatus.hasConnection()) {
      if (context.mounted) AppToast.show(context, NetworkStatus.noInternetMessage);
      return;
    }
    final session = await _sessionFuture;
    await FirebaseFunctions.instance.httpsCallable('deleteItemCompletely').call({
      'itemId': docId,
      'sellerUid': session?.sellerId ?? '',
    });
    if (mounted) {
      setState(() => _itemCaches.removeDoc(docId));
    }
    if (!context.mounted) return;
    AppToast.show(context, 'Item deleted');
  }

  Future<void> _confirmDelete(BuildContext context, String docId, Map<String, dynamic> item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 36),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(padding: EdgeInsets.symmetric(vertical: 22), child: Text('Delete !', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w500))),
            const Divider(height: 1),
            SizedBox(
              height: 58,
              child: Row(
                children: [
                  Expanded(child: TextButton(onPressed: () => Navigator.pop(context, false), style: TextButton.styleFrom(foregroundColor: Colors.black, shape: const RoundedRectangleBorder()), child: const Text('No', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)))),
                  const VerticalDivider(width: 1),
                  Expanded(child: TextButton(onPressed: () => Navigator.pop(context, true), style: TextButton.styleFrom(foregroundColor: Colors.red, shape: const RoundedRectangleBorder()), child: const Text('Yes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.red)))),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (confirm == true && context.mounted) await _deleteItem(context, docId);
  }

  Future<void> _confirmRenew(BuildContext context, String docId, Map<String, dynamic> item) async {
    if (!await SellerSessionGuard.ensureActive(context, onInvalid: widget.onSessionInvalid ?? () {})) return;
    if (!context.mounted) return;
    final result = await showDialog<_RenewDialogResult>(
      context: context,
      builder: (_) => _RenewDialog(initialPrice: _renewPriceText(item), initialUnit: _renewPriceUnit(item), priceUnits: _priceUnits, normalizePrice: _normalizeRenewPrice),
    );

    if (result == null || !mounted) return;
    if (!await NetworkStatus.hasConnection()) {
      if (context.mounted) AppToast.show(context, NetworkStatus.noInternetMessage);
      return;
    }

    final formattedPrice = _formatRenewPrice(result.priceNumber);
    await FirebaseFirestore.instance.collection('items').doc(docId).update({
      'item_price': 'OMR $formattedPrice ${result.priceUnit}',
      'price_number': result.priceNumber,
      'price_unit': result.priceUnit,
      'time_period_days': FieldValue.delete(),
      'time_period_extra_hours': FieldValue.delete(),
      'time_period_hours': FieldValue.delete(),
      'expires_at': Timestamp.fromDate(DateTime.now().add(const Duration(hours: 3))),
      'updated_at': FieldValue.serverTimestamp(),
    });

    if (!mounted) return;
    await reloadItems();
    if (!mounted) return;
    AppToast.show(this.context, 'Live item renewed');
  }

  Future<void> _openEdit(BuildContext context, String docId, Map<String, dynamic> item) async {
    if (!await SellerSessionGuard.ensureActive(context, onInvalid: widget.onSessionInvalid ?? () {})) return;
    if (!context.mounted) return;
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => ItemEditPage(
          docId: docId,
          itemData: item,
          onSessionInvalid: widget.onSessionInvalid,
        ),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _getFilteredDocs(DateTime now) {
    return _activeCache.docs
        .where((doc) => _isItemActive(doc.data(), now))
        .where((doc) => _matchesSelectedStatus(doc.data()))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SellerSession?>(
      future: _sessionFuture,
      builder: (context, sessionSnapshot) {
        final activeCache = _activeCache;
        final isSessionLoading =
            sessionSnapshot.connectionState == ConnectionState.waiting;
        final session = sessionSnapshot.data;
        if (session == null && !isSessionLoading) {
          return const Center(child: Text('Please login again'));
        }
        final bottomSpacerHeight = MediaQuery.viewPaddingOf(context).bottom + 90;

        return Stack(
          children: [
            ValueListenableBuilder<DateTime>(
              valueListenable: _nowNotifier,
              builder: (context, now, _) {
                final docs = _getFilteredDocs(now);

                return DecoratedBox(
                  decoration: BoxDecoration(
                    color: _selectedStatus == 'live'
                        ? null
                        : const Color(0xFFF4FBF7),
                    gradient: _selectedStatus == 'live'
                        ? const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0xFFFFE9EC), Color(0xFFF4FBF7)],
                          )
                        : null,
                  ),
                  child: AppPullRefresh(
                    onRefresh: reloadItems,
                    indicatorTop: 132,
                    child: CustomScrollView(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        const SliverToBoxAdapter(child: SizedBox(height: 8)),
                        SliverToBoxAdapter(
                          child: _ListingsStatusTabs(
                            selectedStatus: _selectedStatus,
                            onChanged: (status) {
                              if (status != _selectedStatus) {
                                FocusManager.instance.primaryFocus?.unfocus();
                                setState(() {
                                  _selectedStatus = status;
                                  _nowNotifier.value = DateTime.now();
                                });
                                if (_activeCache.docs.isEmpty && !_activeCache.isLoading) {
                                  _loadInitial();
                                }
                              }
                            },
                          ),
                        ),
                        if ((docs.isEmpty && activeCache.isLoading) ||
                            (isSessionLoading && docs.isEmpty))
                          const SliverToBoxAdapter(
                            child: _ListingsSkeletonGrid(),
                          )
                        else if (docs.isEmpty && !activeCache.isLoading)
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: activeCache.error != null &&
                                    NetworkStatus.isOfflineError(activeCache.error!)
                                ? OfflineState(onRetry: reloadItems)
                                : Center(
                                    child: Text(
                                      _selectedStatus == 'live'
                                          ? 'No live items listed yet'
                                          : 'No items listed yet',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ),
                          )
                        else ...[
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(2, 4, 2, 12),
                            sliver: SliverGrid.builder(
                              key: ValueKey(
                                _selectedStatus + widget.refreshTick.toString(),
                              ),
                              itemCount: docs.length,
                              addAutomaticKeepAlives: false,
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 4,
                                mainAxisSpacing: 2,
                                childAspectRatio: 0.58,
                              ),
                              itemBuilder: (context, index) {
                                final doc = docs[index];
                                final data = doc.data();
                                return _ListingManageCard(
                                  key: ValueKey(doc.id),
                                  docId: doc.id,
                                  item: data,
                                  uploadedAgo: _uploadedAgo(
                                    data['created_at'],
                                    now,
                                  ),
                                  expiryText: _expiryText(data, now),
                                  formatPrice: formatPrice,
                                  onEdit: _openEdit,
                                  onRenew: _confirmRenew,
                                  onDelete: _confirmDelete,
                                );
                              },
                            ),
                          ),
                          if (activeCache.isLoading)
                            const SliverToBoxAdapter(
                              child: _ListingsSkeletonGrid(),
                            ),
                        ],
                        SliverToBoxAdapter(
                          child: SizedBox(height: bottomSpacerHeight),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _ListingsStatusTabs extends StatelessWidget {
  const _ListingsStatusTabs({required this.selectedStatus, required this.onChanged});

  final String selectedStatus;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 40,
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.black.withValues(alpha: 0.18)), borderRadius: BorderRadius.circular(8)),
          child: Row(
            children: [
              Expanded(child: _ListingsStatusTabButton(text: 'POSTINGS', isSelected: selectedStatus == 'post', selectedColor: const Color(0xFF001341), onTap: () => onChanged('post'), borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)))),
              Container(width: 1, color: Colors.black.withValues(alpha: 0.18)),
              Expanded(child: _ListingsStatusTabButton(text: 'LIVE', isSelected: selectedStatus == 'live', selectedColor: const Color(0xFFFF7801), onTap: () => onChanged('live'), borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)))),
            ],
          ),
        ),
      ),
    );
  }
}

class _ListingsStatusTabButton extends StatelessWidget {
  const _ListingsStatusTabButton({required this.text, required this.isSelected, required this.selectedColor, required this.onTap, required this.borderRadius});

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
        child: Center(child: ResponsiveText(text, style: TextStyle(color: isSelected ? Colors.white : Colors.black, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 0))),
      ),
    );
  }
}

class _RenewDialogResult {
  const _RenewDialogResult({required this.priceNumber, required this.priceUnit});
  final String priceNumber;
  final String priceUnit;
}

class _RenewDialog extends StatefulWidget {
  const _RenewDialog({required this.initialPrice, required this.initialUnit, required this.priceUnits, required this.normalizePrice});
  final String initialPrice;
  final String initialUnit;
  final List<String> priceUnits;
  final String? Function(String value) normalizePrice;
  @override
  State<_RenewDialog> createState() => _RenewDialogState();
}

class _RenewDialogState extends State<_RenewDialog> {
  late final TextEditingController _priceController;
  late String _selectedUnit;
  late String _lastValidPriceText;
  String? _priceError;
  @override
  void initState() {
    super.initState();
    _priceController = TextEditingController(text: _formatEditingPrice(widget.initialPrice));
    _lastValidPriceText = _priceController.text;
    _selectedUnit = widget.initialUnit;
  }
  @override
  void dispose() { _priceController.dispose(); super.dispose(); }

  void _handlePriceChanged(String value) {
    final raw = value.replaceAll(',', '');
    if ('.'.allMatches(raw).length > 1) {
      _setPriceText(_lastValidPriceText);
      return;
    }
    final next = raw.startsWith('.') ? '0$raw' : raw;
    if (next.isNotEmpty && !RegExp(r'^\d+\.?\d*$').hasMatch(next)) {
      _setPriceText(_lastValidPriceText);
      return;
    }
    final parsed = double.tryParse(next);
    if (parsed != null && parsed > maxAllowedPrice) {
      _setPriceText(_lastValidPriceText);
      return;
    }
    final formatted = _formatEditingPrice(next);
    _lastValidPriceText = formatted;
    if (formatted != value) _setPriceText(formatted);
    if (_priceError != null) setState(() => _priceError = null);
  }

  void _setPriceText(String value) {
    _priceController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  String _formatEditingPrice(String value) {
    final clean = value.replaceAll(',', '');
    if (clean.isEmpty) return '';
    final parts = clean.split('.');
    final whole = _formatWholeNumber(parts.first);
    if (clean.endsWith('.')) return '$whole.';
    return parts.length == 2 ? '$whole.${parts.last}' : whole;
  }

  String _formatWholeNumber(String value) {
    final digits = value.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      final remaining = digits.length - i;
      buffer.write(digits[i]);
      if (remaining > 1 && remaining % 3 == 1) buffer.write(',');
    }
    return buffer.toString();
  }

  void _submit() {
    final normalized = widget.normalizePrice(_priceController.text);
    if (normalized == null) { setState(() => _priceError = 'Price Required'); return; }
    Navigator.pop(context, _RenewDialogResult(priceNumber: normalized, priceUnit: _selectedUnit));
  }
  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 36),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(padding: EdgeInsets.symmetric(vertical: 22), child: Text('RENEW', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w500))),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
            child: Row(
              children: [
                Expanded(flex: 3, child: TextField(controller: _priceController, keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: const [PriceInputFormatter()], onChanged: _handlePriceChanged, decoration: InputDecoration(isDense: true, labelText: _priceError ?? 'Price', errorText: _priceError, prefixIcon: const Padding(padding: EdgeInsets.all(12), child: RiyalCurrencyIcon(size: 22)), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))))),
                const SizedBox(width: 10),
                Expanded(flex: 2, child: DropdownButtonFormField<String>(initialValue: _selectedUnit, decoration: InputDecoration(isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))), items: widget.priceUnits.map((unit) => DropdownMenuItem(value: unit, child: Text(unit.replaceFirst('/ ', '')))).toList(), onChanged: (value) { if (value != null) setState(() => _selectedUnit = value); })),
              ],
            ),
          ),
          const Divider(height: 1),
          SizedBox(
            height: 58,
            child: Row(
              children: [
                Expanded(child: TextButton(onPressed: () => Navigator.pop(context), style: TextButton.styleFrom(foregroundColor: Colors.black, shape: const RoundedRectangleBorder()), child: const Text('No', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)))),
                const VerticalDivider(width: 1),
                Expanded(child: TextButton(onPressed: _submit, style: TextButton.styleFrom(foregroundColor: Colors.red, shape: const RoundedRectangleBorder()), child: const Text('Yes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.red)))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ListingManageCard extends StatelessWidget {
  const _ListingManageCard({super.key, required this.docId, required this.item, required this.uploadedAgo, required this.expiryText, required this.formatPrice, required this.onEdit, required this.onRenew, required this.onDelete});
  final String docId; final Map<String, dynamic> item; final String uploadedAgo; final String expiryText; final String Function(Object? value) formatPrice; final void Function(BuildContext context, String docId, Map<String, dynamic> item) onEdit; final void Function(BuildContext context, String docId, Map<String, dynamic> item) onRenew; final void Function(BuildContext context, String docId, Map<String, dynamic> item) onDelete;

  @override
  Widget build(BuildContext context) {
    final isLiveItem = item['status']?.toString() == 'live';
    return Stack(
      children: [
        ItemCard(docId: docId, item: item, isCompact: true, isLivePage: isLiveItem, liveMarkerTop: isLiveItem ? -37 : -29, uploadedAgoOverride: uploadedAgo),
        Positioned(top: isLiveItem ? 36 : 30, right: 7, child: _LiveExpiryBadge(text: expiryText)),
        Positioned(top: isLiveItem ? 70 : 58, right: 7, child: _ListingQuickActions(isLiveItem: isLiveItem, onEdit: () => onEdit(context, docId, item), onRenew: () => onRenew(context, docId, item), onDelete: () => onDelete(context, docId, item))),
      ],
    );
  }
}

class _ListingsSkeletonGrid extends StatelessWidget {
  const _ListingsSkeletonGrid();

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

class _ListingQuickActions extends StatelessWidget {
  const _ListingQuickActions({required this.isLiveItem, required this.onEdit, required this.onRenew, required this.onDelete});
  final bool isLiveItem; final VoidCallback onEdit; final VoidCallback onRenew; final VoidCallback onDelete;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.end, children: [_ActionPill(text: 'Edit', color: const Color(0xFF128CFF), onTap: onEdit), if (isLiveItem) ...[const SizedBox(height: 12), _ActionPill(text: 'Renew', color: const Color(0xFF25D366), onTap: onRenew)], const SizedBox(height: 12), _ActionPill(text: 'Delete', color: Colors.red, onTap: onDelete)]);
}

class _LiveExpiryBadge extends StatelessWidget {
  const _LiveExpiryBadge({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4), decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.72), borderRadius: BorderRadius.circular(8)), child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)));
}

class _ActionPill extends StatelessWidget {
  const _ActionPill({required this.text, required this.color, required this.onTap});
  final String text; final Color color; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(color: Colors.transparent, borderRadius: BorderRadius.circular(8), child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(8), child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration(color: color, border: Border.all(color: Colors.black, width: 1.2), borderRadius: BorderRadius.circular(8)), child: ResponsiveText(text, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)))));
}
