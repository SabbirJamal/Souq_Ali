import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'seller_home_page.dart';
import 'seller_session.dart';
import 'widgets/app_status_bar.dart';
import 'widgets/item_card.dart';
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
      MaterialPageRoute(
        builder: (_) => SellerHomePage(
          isSellerMode: session != null,
          initialTabIndex: index,
        ),
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
      MaterialPageRoute(builder: (_) => const SellerHomePage(isSellerMode: false)),
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
      MaterialPageRoute(
        builder: (_) => const SellerHomePage(
          isSellerMode: true,
          initialTabIndex: 4,
        ),
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
        backgroundColor: const Color(0xFFF4FBF7),
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
  Widget build(BuildContext context) {
    final sellerDocId = _sellerDocId;
    final topInset = MediaQuery.paddingOf(context).top;

    return Stack(
      children: [
        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _sellerStream,
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

            return CustomScrollView(
              slivers: [
                if (!isOwnProfile)
                  SliverToBoxAdapter(
                    child: _ProfileScrollableHeader(onBack: onBack),
                  ),
                SliverToBoxAdapter(
                  child: _SellerProfileTop(
                    sellerName: sellerName,
                    crNumber: crNumber,
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
                    },
                  ),
                ),
                _SellerActivePosts(
                  sellerId: sellerDocId,
                  selectedStatus: _selectedStatus,
                ),
              ],
            );
          },
        ),
        if (isOwnProfile)
          _ProfileSettingsMenu(onSettings: onSettings, onLogout: onLogout)
        else ...[
          if (onBack != null)
            Positioned(
              top: topInset,
              left: 14,
              child: _ProfileFloatingBackButton(onBack: onBack!),
            ),
          Positioned(
            top: topInset,
            right: 14,
            child: const _ProfileFloatingShareButton(),
          ),
        ],
      ],
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
  const _ProfileScrollableHeader({required this.onBack});

  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 56,
          color: const Color(0xFFF4FBF7),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Stack(
            alignment: Alignment.center,
            children: [
              const SizedBox(
                height: 56,
                width: 152,
                child: Image(
                  image: AssetImage('assets/branding/logo.png'),
                  fit: BoxFit.cover,
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

class _ProfileFloatingShareButton extends StatelessWidget {
  const _ProfileFloatingShareButton();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: _BorderedHeaderButton(
        width: 88,
        onTap: () {},
        backgroundColor: const Color(0xFFFF7801),
        borderColor: null,
        child: const Text(
          'Share',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _BorderedHeaderButton extends StatelessWidget {
  const _BorderedHeaderButton({
    required this.onTap,
    required this.child,
    this.width = 44,
    this.backgroundColor = Colors.white,
    this.borderColor = Colors.black,
    this.circular = false,
  });

  final VoidCallback onTap;
  final Widget child;
  final double width;
  final Color backgroundColor;
  final Color? borderColor;
  final bool circular;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(circular ? 999 : 10);
    return Material(
      color: backgroundColor,
      borderRadius: borderRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        child: Container(
          width: width,
          height: circular ? width : 42,
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
      color: const Color(0xFFF4FBF7),
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
      color: const Color(0xFFF4FBF7),
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
    required this.sellerId,
    required this.selectedStatus,
  });

  final String sellerId;
  final String selectedStatus;

  @override
  State<_SellerActivePosts> createState() => _SellerActivePostsState();
}

class _SellerActivePostsState extends State<_SellerActivePosts> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _itemsStream =
      FirebaseFirestore.instance
          .collection('items')
          .where('seller_uid', isEqualTo: widget.sellerId)
          .snapshots();

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _itemsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SliverFillRemaining(
            hasScrollBody: false,
            child: _SellerProfilePostsSkeleton(),
          );
        }
        if (snapshot.hasError) {
          return SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text('Error: ${snapshot.error}')),
          );
        }

        final docs = (snapshot.data?.docs ?? [])
            .where((doc) {
              final item = doc.data();
              return _isItemActive(item, now) &&
                  _matchesProfileStatus(item, widget.selectedStatus);
            })
            .toList()
          ..sort((a, b) {
            final aTime = a.data()['created_at'];
            final bTime = b.data()['created_at'];
            final aDate = aTime is Timestamp
                ? aTime.toDate()
                : DateTime.fromMillisecondsSinceEpoch(0);
            final bDate = bTime is Timestamp
                ? bTime.toDate()
                : DateTime.fromMillisecondsSinceEpoch(0);
            return bDate.compareTo(aDate);
          });

        if (docs.isEmpty) {
          return const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Text(
                'No active posts',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            ),
          );
        }

        return SliverPadding(
          padding: const EdgeInsets.fromLTRB(2, 4, 2, 12),
          sliver: SliverToBoxAdapter(
            child: _SellerProfileGrid(docs: docs),
          ),
        );
      },
    );
  }
}

class _SellerProfileGrid extends StatelessWidget {
  const _SellerProfileGrid({required this.docs});

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;

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
        Expanded(child: _SellerProfileColumn(docs: leftDocs)),
        const SizedBox(width: 4),
        Expanded(child: _SellerProfileColumn(docs: rightDocs)),
      ],
    );
  }
}

class _SellerProfilePostsSkeleton extends StatelessWidget {
  const _SellerProfilePostsSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 8, 2, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Expanded(child: ItemCardSkeleton(isCompact: true)),
          SizedBox(width: 4),
          Expanded(child: ItemCardSkeleton(isCompact: true)),
        ],
      ),
    );
  }
}

class _SellerProfileColumn extends StatelessWidget {
  const _SellerProfileColumn({required this.docs});

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: docs
          .map((doc) => ItemCard(
                docId: doc.id,
                item: doc.data(),
                isCompact: true,
                replaceOnOpen: true,
              ))
          .toList(),
    );
  }
}

bool _matchesProfileStatus(Map<String, dynamic> item, String selectedStatus) {
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
