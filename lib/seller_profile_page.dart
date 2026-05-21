import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'seller_home_page.dart';
import 'seller_session.dart';
import 'widgets/item_card.dart';

class SellerProfilePage extends StatelessWidget {
  const SellerProfilePage({
    super.key,
    required this.sellerId,
    required this.sellerPhone,
    required this.fallbackName,
  });

  final String sellerId;
  final String sellerPhone;
  final String fallbackName;

  Future<void> _goHome(BuildContext context) async {
    final session = await SellerSession.current();
    if (!context.mounted) {
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => SellerHomePage(isSellerMode: session != null),
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
      builder: (context) => AlertDialog(
        title: const Center(
          child: Text('Logout !', style: TextStyle(fontSize: 30)),
        ),
        contentPadding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
        actionsPadding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.black,
                    side: const BorderSide(color: Colors.black, width: 2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('No', style: TextStyle(fontSize: 28)),
                ),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.black, width: 2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Yes',
                    style: TextStyle(fontSize: 28, color: Colors.red),
                  ),
                ),
              ),
            ],
          ),
        ],
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
    final sellerDocId = sellerId.isNotEmpty ? sellerId : sellerPhone;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.black,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        body: Stack(
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
                      ),
                    ),
                    _SellerActivePosts(sellerId: sellerDocId),
                  ],
                );
              },
            ),
            _ProfileSettingsMenu(
              onSettings: () => _openSettings(context),
              onLogout: () => _confirmLogout(context),
            ),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: 0,
          onTap: (_) => _goHome(context),
          type: BottomNavigationBarType.fixed,
          selectedItemColor: const Color(0xFFFF7801),
          unselectedItemColor: Colors.grey,
          selectedFontSize: 0,
          unselectedFontSize: 0,
          showSelectedLabels: false,
          showUnselectedLabels: false,
          iconSize: 24,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
            BottomNavigationBarItem(
              icon: Icon(Icons.play_circle_fill),
              label: 'Stories',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.add_circle_outline),
              label: 'Add',
            ),
            BottomNavigationBarItem(icon: Icon(Icons.list_alt), label: 'Listings'),
            BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
          ],
        ),
      ),
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

class _SellerProfileTop extends StatelessWidget {
  const _SellerProfileTop({
    required this.sellerName,
    required this.crNumber,
  });

  final String sellerName;
  final String crNumber;

  @override
  Widget build(BuildContext context) {
    final topPadding = 36 + (MediaQuery.sizeOf(context).height * 0.05);
    return Container(
      width: double.infinity,
      color: const Color(0xFFF4FBF7),
      padding: EdgeInsets.fromLTRB(18, topPadding, 18, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            sellerName.isEmpty ? 'Seller' : sellerName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (crNumber.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              'CR No. $crNumber',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
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
