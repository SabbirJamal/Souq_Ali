import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

import '../item_edit_page.dart';
import '../seller_session.dart';
import '../seller_session_guard.dart';
import '../utils/formatters.dart';
import '../widgets/app_toast.dart';
import '../widgets/item_card.dart';
import '../widgets/price_with_currency.dart';

class SellerListingsTab extends StatefulWidget {
  const SellerListingsTab({super.key, this.refreshTick = 0, this.onSessionInvalid});

  final int refreshTick;
  final VoidCallback? onSessionInvalid;

  @override
  State<SellerListingsTab> createState() => _SellerListingsTabState();
}

class _SellerListingsTabState extends State<SellerListingsTab> {
  static const _pageSize = 15;
  static const _priceUnits = ['/ kg', '/ ton', '/ box', '/ bag'];

  late final Future<SellerSession?> _sessionFuture;
  final ValueNotifier<DateTime> _nowNotifier = ValueNotifier(DateTime.now());
  final _scrollController = ScrollController();
  
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _allDocs = [];
  String _selectedStatus = 'post';
  bool _isLoading = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _sessionFuture = SellerSession.current();
    _loadInitial();
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _isLoading || !_hasMore) return;
    if (_scrollController.position.pixels > _scrollController.position.maxScrollExtent - 800) {
      _loadMore();
    }
  }

  Future<void> _loadInitial() async {
    final session = await _sessionFuture;
    if (session == null) return;
    await _fetchPage(session, isInitial: true);
  }

  Future<void> _loadMore() async {
    final session = await _sessionFuture;
    if (session == null) return;
    await _fetchPage(session, isInitial: false);
  }

  Future<void> _fetchPage(SellerSession session, {required bool isInitial}) async {
    if (_isLoading || (!isInitial && !_hasMore)) return;
    setState(() => _isLoading = true);

    try {
      var query = FirebaseFirestore.instance
          .collection('items')
          .where('seller_uid', isEqualTo: session.sellerId)
          .limit(_pageSize * 4);

      final snapshot = await query.get();
      if (!mounted) return;

      var newDocs = snapshot.docs.toList()
        ..sort((a, b) {
          final aTime = _createdAt(a.data()) ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bTime = _createdAt(b.data()) ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bTime.compareTo(aTime);
        });
      if (newDocs.isEmpty && isInitial) {
        final legacySnapshot = await FirebaseFirestore.instance
            .collection('items')
            .where('seller_phone', isEqualTo: session.phoneNumber)
            .limit(_pageSize * 4)
            .get();
        newDocs = legacySnapshot.docs.toList()
          ..sort((a, b) {
            final aTime = _createdAt(a.data()) ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bTime = _createdAt(b.data()) ?? DateTime.fromMillisecondsSinceEpoch(0);
            return bTime.compareTo(aTime);
          });
      }
      setState(() {
        if (isInitial) _allDocs.clear();
        _allDocs.addAll(newDocs);
        _hasMore = false;
        _isLoading = false;
      });
    } catch (e) {
      try {
        var fallbackQuery = FirebaseFirestore.instance
            .collection('items')
            .where('seller_uid', isEqualTo: session.sellerId)
            .limit(_pageSize * 4);

        final snapshot = await fallbackQuery.get();
        if (!mounted) return;
        var newDocs = snapshot.docs.toList()
          ..sort((a, b) {
            final aTime = _createdAt(a.data()) ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bTime = _createdAt(b.data()) ?? DateTime.fromMillisecondsSinceEpoch(0);
            return bTime.compareTo(aTime);
          });
        if (newDocs.isEmpty && isInitial) {
          final legacySnapshot = await FirebaseFirestore.instance
              .collection('items')
              .where('seller_phone', isEqualTo: session.phoneNumber)
              .limit(_pageSize * 4)
              .get();
          newDocs = legacySnapshot.docs.toList()
            ..sort((a, b) {
              final aTime = _createdAt(a.data()) ?? DateTime.fromMillisecondsSinceEpoch(0);
              final bTime = _createdAt(b.data()) ?? DateTime.fromMillisecondsSinceEpoch(0);
              return bTime.compareTo(aTime);
            });
        }
        setState(() {
          if (isInitial) _allDocs.clear();
          _allDocs.addAll(newDocs);
          _hasMore = false;
          _isLoading = false;
        });
      } catch (_) {
        if (mounted) setState(() => _isLoading = false);
      }
    }
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
    final status = item['status']?.toString();
    if (_selectedStatus == 'post') return status == null || status.isEmpty || status == 'post';
    return status == _selectedStatus;
  }

  String _uploadedAgo(Object? value, DateTime now) {
    DateTime? uploadedAt;
    if (value is Timestamp) uploadedAt = value.toDate();
    else if (value is DateTime) uploadedAt = value;
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
    final cleanValue = value.replaceAll(',', '').trim();
    if (!RegExp(r'^\d+(\.\d{0,3})?$').hasMatch(cleanValue)) return null;
    final parsed = double.tryParse(cleanValue);
    if (parsed == null || parsed <= 0) return null;
    return parsed.toStringAsFixed(3);
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

  Future<void> _deleteItem(BuildContext context, String docId, Map<String, dynamic> item) async {
    if (!await SellerSessionGuard.ensureActive(context, onInvalid: widget.onSessionInvalid ?? () {})) return;
    await _deleteItemStorageFiles(item);
    await _deleteSeenRecord(docId);
    await FirebaseFirestore.instance.collection('items').doc(docId).delete();
    if (mounted) {
      setState(() => _allDocs.removeWhere((doc) => doc.id == docId));
    }
    if (!context.mounted) return;
    AppToast.show(context, 'Item deleted');
  }

  Future<void> _deleteItemStorageFiles(Map<String, dynamic> item) async {
    final urls = <String>{};
    final imageUrls = item['image_urls'];
    if (imageUrls is List) {
      for (final url in imageUrls) {
        final text = url?.toString().trim() ?? '';
        if (text.isNotEmpty) urls.add(text);
      }
    }

    final mediaFiles = item['media_files'];
    if (mediaFiles is List) {
      for (final media in mediaFiles) {
        if (media is! Map) continue;
        final url = media['url']?.toString().trim() ?? '';
        final thumbnailUrl = media['thumbnail_url']?.toString().trim() ?? '';
        if (url.isNotEmpty) urls.add(url);
        if (thumbnailUrl.isNotEmpty) urls.add(thumbnailUrl);
      }
    }

    final legacyAudioUrl = item['audio_description_url']?.toString().trim() ?? '';
    if (legacyAudioUrl.isNotEmpty) urls.add(legacyAudioUrl);

    await Future.wait(
      urls.map((url) async {
        try {
          await FirebaseStorage.instance.refFromURL(url).delete();
        } catch (_) {}
      }),
    );
  }

  Future<void> _deleteSeenRecord(String docId) async {
    try {
      final seenRef = FirebaseFirestore.instance.collection('item_seen').doc(docId);
      final viewers = await seenRef.collection('viewers').limit(100).get();
      final batch = FirebaseFirestore.instance.batch();
      for (final viewer in viewers.docs) {
        batch.delete(viewer.reference);
      }
      batch.delete(seenRef);
      await batch.commit();
    } catch (_) {}
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

    if (confirm == true && context.mounted) await _deleteItem(context, docId, item);
  }

  Future<void> _confirmRenew(BuildContext context, String docId, Map<String, dynamic> item) async {
    if (!await SellerSessionGuard.ensureActive(context, onInvalid: widget.onSessionInvalid ?? () {})) return;
    if (!context.mounted) return;
    final result = await showDialog<_RenewDialogResult>(
      context: context,
      builder: (_) => _RenewDialog(initialPrice: _renewPriceText(item), initialUnit: _renewPriceUnit(item), priceUnits: _priceUnits, normalizePrice: _normalizeRenewPrice),
    );

    if (result == null || !mounted) return;

    final formattedPrice = _formatRenewPrice(result.priceNumber);
    await FirebaseFirestore.instance.collection('items').doc(docId).update({
      'item_price': 'OMR $formattedPrice ${result.priceUnit}',
      'price_number': result.priceNumber,
      'price_unit': result.priceUnit,
      'time_period_days': 0,
      'time_period_extra_hours': 2,
      'time_period_hours': 2,
      'expires_at': Timestamp.fromDate(DateTime.now().add(const Duration(hours: 2))),
      'updated_at': FieldValue.serverTimestamp(),
    });

    if (!mounted) return;
    AppToast.show(this.context, 'Live item renewed');
  }

  Future<void> _openEdit(BuildContext context, String docId, Map<String, dynamic> item) async {
    if (!await SellerSessionGuard.ensureActive(context, onInvalid: widget.onSessionInvalid ?? () {})) return;
    if (!context.mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => ItemEditPage(docId: docId, itemData: item, onSessionInvalid: widget.onSessionInvalid)));
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _getFilteredDocs(DateTime now) {
    return _allDocs
        .where((doc) => _isItemActive(doc.data(), now))
        .where((doc) => _matchesSelectedStatus(doc.data()))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SellerSession?>(
      future: _sessionFuture,
      builder: (context, sessionSnapshot) {
        if (sessionSnapshot.connectionState == ConnectionState.waiting && _allDocs.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        final session = sessionSnapshot.data;
        if (session == null) return const Center(child: Text('Please login again'));

        return Stack(
          children: [
            ValueListenableBuilder<DateTime>(
              valueListenable: _nowNotifier,
              builder: (context, now, _) {
                final docs = _getFilteredDocs(now);

                return CustomScrollView(
                  controller: _scrollController,
                  slivers: [
                    const SliverToBoxAdapter(child: _ListingsScrollableHeader()),
                    SliverToBoxAdapter(child: _SellerInfoHeader(session: session)),
                    SliverToBoxAdapter(
                      child: _ListingsStatusTabs(
                        selectedStatus: _selectedStatus,
                        onChanged: (status) {
                          if (status != _selectedStatus) {
                            FocusManager.instance.primaryFocus?.unfocus();
                            setState(() {
                              _selectedStatus = status;
                              _allDocs.clear();
                              _hasMore = true;
                              _nowNotifier.value = DateTime.now();
                            });
                            _loadInitial();
                          }
                        },
                      ),
                    ),
                    if (docs.isEmpty && !_isLoading)
                      SliverFillRemaining(hasScrollBody: false, child: Center(child: Text(_selectedStatus == 'live' ? 'No live items listed yet' : 'No items listed yet', style: const TextStyle(fontSize: 16, color: Colors.grey))))
                    else ...[
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(2, 4, 2, 12),
                        sliver: SliverGrid.builder(
                          key: ValueKey(_selectedStatus + widget.refreshTick.toString()),
                          itemCount: docs.length,
                          addAutomaticKeepAlives: false,
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 4, mainAxisSpacing: 2, childAspectRatio: 0.58),
                          itemBuilder: (context, index) {
                            final doc = docs[index];
                            final data = doc.data();
                            return _ListingManageCard(
                              key: ValueKey(doc.id),
                              docId: doc.id,
                              item: data,
                              uploadedAgo: _uploadedAgo(data['created_at'], now),
                              expiryText: _expiryText(data, now),
                              formatPrice: formatPrice,
                              onEdit: _openEdit,
                              onRenew: _confirmRenew,
                              onDelete: _confirmDelete,
                            );
                          },
                        ),
                      ),
                      if (_isLoading) const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Center(child: CircularProgressIndicator(color: Color(0xFFFF7801))))),
                    ],
                  ],
                );
              },
            ),
            const Positioned(top: 8, right: 14, child: _FloatingShareButton()),
          ],
        );
      },
    );
  }
}

class _ListingsScrollableHeader extends StatelessWidget {
  const _ListingsScrollableHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      width: double.infinity,
      color: const Color(0xFFF4FBF7),
      alignment: Alignment.center,
      child: const SizedBox(
        height: 56,
        width: 152,
        child: Image(
          image: AssetImage('assets/branding/logo.png'),
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

class _FloatingShareButton extends StatelessWidget {
  const _FloatingShareButton();

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: () {},
      style: OutlinedButton.styleFrom(
        backgroundColor: const Color(0xFFFF7801),
        foregroundColor: Colors.white,
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        minimumSize: const Size(82, 38),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: const Text('Share', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
    );
  }
}

class _SellerInfoHeader extends StatelessWidget {
  const _SellerInfoHeader({required this.session});

  final SellerSession session;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('sellers').doc(session.sellerId).snapshots(),
      builder: (context, snapshot) {
        final seller = snapshot.data?.data() ?? {};
        final sellerName = seller['name']?.toString().trim() ?? session.name;
        final crNumber = seller['cr_number']?.toString().trim().isNotEmpty == true ? seller['cr_number'].toString().trim() : seller['crNumber']?.toString().trim() ?? '';
        final topLine = [if (sellerName.trim().isNotEmpty) sellerName.trim(), if (crNumber.isNotEmpty) 'CR No. $crNumber'].join(' | ');
        final phoneNumber = formatSellerPhone(session.phoneNumber);

        return Container(
          width: double.infinity,
          color: const Color(0xFFF4FBF7),
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (topLine.isNotEmpty) FittedBox(fit: BoxFit.scaleDown, child: Text(topLine, maxLines: 1, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black, fontSize: 15, fontWeight: FontWeight.bold))),
              if (phoneNumber.isNotEmpty) ...[
                if (topLine.isNotEmpty) const SizedBox(height: 5),
                Text(phoneNumber, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black, fontSize: 14, fontWeight: FontWeight.bold)),
              ],
            ],
          ),
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
      color: const Color(0xFFF4FBF7),
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
      child: Container(
        height: 40,
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.black.withValues(alpha: 0.18)), borderRadius: BorderRadius.circular(8)),
        child: Row(
          children: [
            Expanded(child: _ListingsStatusTabButton(text: 'POSTINGS', isSelected: selectedStatus == 'post', selectedColor: const Color(0xFF001341), onTap: () => onChanged('post'))),
            Container(width: 1, color: Colors.black.withValues(alpha: 0.18)),
            Expanded(child: _ListingsStatusTabButton(text: 'LIVE', isSelected: selectedStatus == 'live', selectedColor: const Color(0xFFFF7801), onTap: () => onChanged('live'))),
          ],
        ),
      ),
    );
  }
}

class _ListingsStatusTabButton extends StatelessWidget {
  const _ListingsStatusTabButton({required this.text, required this.isSelected, required this.selectedColor, required this.onTap});

  final String text;
  final bool isSelected;
  final Color selectedColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? selectedColor : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Center(child: Text(text, style: TextStyle(color: isSelected ? Colors.white : Colors.black, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 0))),
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
  String? _priceError;
  @override
  void initState() {
    super.initState();
    _priceController = TextEditingController(text: widget.initialPrice);
    _selectedUnit = widget.initialUnit;
  }
  @override
  void dispose() { _priceController.dispose(); super.dispose(); }
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
                Expanded(flex: 3, child: TextField(controller: _priceController, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) { if (_priceError != null) setState(() => _priceError = null); }, decoration: InputDecoration(isDense: true, labelText: _priceError ?? 'Price', errorText: _priceError, prefixIcon: const Padding(padding: EdgeInsets.all(12), child: RiyalCurrencyIcon(size: 22)), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))))),
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
  Widget build(BuildContext context) => Material(color: Colors.transparent, borderRadius: BorderRadius.circular(8), child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(8), child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration(color: color, border: Border.all(color: Colors.black, width: 1.2), borderRadius: BorderRadius.circular(8)), child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)))));
}
