import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'seller_home_page.dart';
import 'seller_session.dart';
import 'widgets/item_card.dart';
import 'widgets/profile_image.dart';

class SellerProfilePage extends StatelessWidget {
  const SellerProfilePage({
    super.key,
    required this.sellerId,
    required this.sellerPhone,
    required this.fallbackName,
    required this.fallbackImageUrl,
  });

  final String sellerId;
  final String sellerPhone;
  final String fallbackName;
  final String fallbackImageUrl;

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
                final profileImageUrl =
                    seller['profile_image_url']?.toString().trim().isNotEmpty ==
                        true
                    ? seller['profile_image_url'].toString().trim()
                    : fallbackImageUrl;
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
                        profileImageUrl: profileImageUrl,
                      ),
                    ),
                    _SellerActivePosts(sellerId: sellerDocId),
                  ],
                );
              },
            ),
            _FloatingProfileBackButton(onBack: () => Navigator.pop(context)),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: 0,
          onTap: (_) => _goHome(context),
          type: BottomNavigationBarType.fixed,
          selectedItemColor: const Color(0xFFFF7801),
          unselectedItemColor: Colors.grey,
          selectedFontSize: 11,
          unselectedFontSize: 11,
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
            BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
          ],
        ),
      ),
    );
  }
}

class _FloatingProfileBackButton extends StatelessWidget {
  const _FloatingProfileBackButton({required this.onBack});

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
        elevation: 3,
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

class _SellerProfileTop extends StatelessWidget {
  const _SellerProfileTop({
    required this.sellerName,
    required this.crNumber,
    required this.profileImageUrl,
  });

  final String sellerName;
  final String crNumber;
  final String profileImageUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFF4FBF7),
      padding: const EdgeInsets.fromLTRB(18, 36, 18, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SellerProfileImage(imageUrl: profileImageUrl),
          const SizedBox(height: 10),
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

class _SellerProfileImage extends StatelessWidget {
  const _SellerProfileImage({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 92,
      height: 92,
      child: ProfileImage(
        imageValue: imageUrl,
        size: 92,
        fallbackColor: Colors.teal,
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
