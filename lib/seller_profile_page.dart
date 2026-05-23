import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'seller_home_page.dart';
import 'seller_session.dart';
import 'widgets/item_card.dart';

class SellerProfileTab extends StatelessWidget {
  const SellerProfileTab({
    super.key,
    required this.onSettings,
    required this.onLogout,
  });

  final VoidCallback onSettings;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SellerSession?>(
      future: SellerSession.current(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final session = snapshot.data;
        if (session == null) {
          return const Center(child: Text('Please login again'));
        }
        return _SellerProfileBody(
          sellerId: session.sellerId,
          sellerPhone: session.phoneNumber,
          fallbackName: session.name,
          isOwnProfile: true,
          onSettings: onSettings,
          onLogout: onLogout,
          onBack: null,
        );
      },
    );
  }
}

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
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.black,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        body: _SellerProfileBody(
          sellerId: sellerId,
          sellerPhone: sellerPhone,
          fallbackName: fallbackName,
          isOwnProfile: isOwnProfile,
          onSettings: () => _openSettings(context),
          onLogout: () => _confirmLogout(context),
          onBack: () => Navigator.pop(context),
        ),
        bottomNavigationBar: SizedBox(
          height: 58,
          child: BottomNavigationBar(
            currentIndex: 4,
            onTap: (index) {
              _openHomeTab(context, index);
            },
            type: BottomNavigationBarType.fixed,
            selectedItemColor: const Color(0xFFFF7801),
            unselectedItemColor: Colors.grey,
            selectedFontSize: 0,
            unselectedFontSize: 0,
            showSelectedLabels: false,
            showUnselectedLabels: false,
            iconSize: 24,
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.home),
                label: 'Home',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.play_circle_fill),
                label: 'Stories',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.add_circle_outline),
                label: 'Add',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.person),
                label: 'Listings',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.settings),
                label: 'Settings',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SellerProfileBody extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final sellerDocId = sellerId.isNotEmpty ? sellerId : sellerPhone;

    return Stack(
      children: [
        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: sellerDocId.isEmpty
              ? null
              : FirebaseFirestore.instance
                    .collection('sellers')
                    .doc(sellerDocId)
                    .snapshots(),
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
                SliverToBoxAdapter(
                  child: _SellerProfileTop(
                    sellerName: sellerName,
                    crNumber: crNumber,
                    sellerPhone: sellerPhone,
                  ),
                ),
                _SellerActivePosts(sellerId: sellerDocId),
              ],
            );
          },
        ),
        if (isOwnProfile)
          _ProfileSettingsMenu(onSettings: onSettings, onLogout: onLogout)
        else if (onBack != null)
          _ProfileBackButton(onBack: onBack!),
        const _ProfileShareButton(),
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

class _ProfileBackButton extends StatelessWidget {
  const _ProfileBackButton({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    return Positioned(
      top: topInset + 8,
      left: 14,
      child: SafeArea(
        top: false,
        child: Material(
          color: Colors.white,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onBack,
            child: const SizedBox(
              width: 42,
              height: 42,
              child: Icon(Icons.arrow_back, color: Colors.black),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileShareButton extends StatelessWidget {
  const _ProfileShareButton();

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    return Positioned(
      top: topInset + 8,
      right: 14,
      child: SafeArea(
        top: false,
        child: Material(
          color: Colors.white,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () {},
            child: const SizedBox(
              width: 42,
              height: 42,
              child: Center(
                child: Text(
                  'Share',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
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
  });

  final String sellerName;
  final String crNumber;
  final String sellerPhone;

  @override
  Widget build(BuildContext context) {
    final topPadding = 56 + (MediaQuery.sizeOf(context).height * 0.05);
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

class _SellerActivePosts extends StatelessWidget {
  const _SellerActivePosts({required this.sellerId});

  final String sellerId;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('items')
          .where('seller_uid', isEqualTo: sellerId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text('Error: ${snapshot.error}')),
          );
        }

        final docs = (snapshot.data?.docs ?? [])
            .where((doc) => _isItemActive(doc.data(), now))
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

class _SellerProfileColumn extends StatelessWidget {
  const _SellerProfileColumn({required this.docs});

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: docs
          .map((doc) => ItemCard(docId: doc.id, item: doc.data(), isCompact: true))
          .toList(),
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
