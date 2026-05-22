import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../item_detail_page.dart';
import '../item_edit_page.dart';
import '../seller_session.dart';
import '../story_repository.dart';
import '../widgets/media_carousel.dart';
import '../widgets/price_with_currency.dart';

class SellerListingsTab extends StatefulWidget {
  const SellerListingsTab({super.key});

  @override
  State<SellerListingsTab> createState() => _SellerListingsTabState();
}

class _SellerListingsTabState extends State<SellerListingsTab> {
  late final Future<SellerSession?> _sessionFuture;
  late DateTime _now;
  Timer? _expiryTimer;

  @override
  void initState() {
    super.initState();
    _sessionFuture = SellerSession.current();
    _now = DateTime.now();
    _expiryTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        setState(() => _now = DateTime.now());
      }
    });
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }

  String _postedDateTime(Object? value) {
    DateTime? postedAt;
    if (value is Timestamp) {
      postedAt = value.toDate();
    } else if (value is DateTime) {
      postedAt = value;
    }
    if (postedAt == null) {
      return 'Posted just now';
    }

    final hour12 = postedAt.hour % 12 == 0 ? 12 : postedAt.hour % 12;
    final minute = postedAt.minute.toString().padLeft(2, '0');
    final period = postedAt.hour >= 12 ? 'PM' : 'AM';
    return 'Posted ${postedAt.day}/${postedAt.month}/${postedAt.year} $hour12:$minute $period';
  }

  String _listingPrice(Object? value) {
    final text = value?.toString().trim() ?? '';
    final match = RegExp(r'\d+(?:\.\d+)?').firstMatch(text);
    if (match != null && (double.tryParse(match.group(0) ?? '') ?? -1) == 0) {
      return 'Contact for price';
    }
    return text;
  }

  DateTime? _expiryAt(Map<String, dynamic> item) {
    final expiresAt = item['expires_at'];
    if (expiresAt is Timestamp) {
      return expiresAt.toDate();
    }
    if (expiresAt is DateTime) {
      return expiresAt;
    }

    final createdAt = item['created_at'];
    final timePeriodHours = item['time_period_hours'];
    DateTime? postedAt;
    if (createdAt is Timestamp) {
      postedAt = createdAt.toDate();
    } else if (createdAt is DateTime) {
      postedAt = createdAt;
    }
    if (postedAt == null || timePeriodHours is! num) {
      return null;
    }
    return postedAt.add(Duration(hours: timePeriodHours.toInt()));
  }

  String _expiryText(Map<String, dynamic> item) {
    final expiryAt = _expiryAt(item);
    if (expiryAt == null) {
      return 'Exp. not set';
    }
    final remaining = expiryAt.difference(_now);
    if (remaining <= Duration.zero) {
      return 'Exp. expired';
    }

    final minutes = (remaining.inSeconds / 60).ceil();
    if (minutes < 60) {
      return 'Exp. in $minutes ${minutes == 1 ? 'min' : 'mins'}';
    }

    final hours = minutes ~/ 60;
    final extraMinutes = minutes % 60;
    final hourText = '$hours ${hours == 1 ? 'hr' : 'hrs'}';
    if (extraMinutes == 0) {
      return 'Exp. in $hourText';
    }
    return 'Exp. in $hourText $extraMinutes mins';
  }

  Future<void> _deleteItem(
    BuildContext context,
    String docId,
    Map<String, dynamic> item,
  ) async {
    final sellerId = item['seller_uid']?.toString() ?? '';
    if (sellerId.isNotEmpty) {
      await const StoryRepository().removeItemVideos(
        sellerId: sellerId,
        itemId: docId,
      );
    }
    await FirebaseFirestore.instance.collection('items').doc(docId).delete();
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Item deleted'),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SellerSession?>(
      future: _sessionFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final session = snapshot.data;
        if (session == null) {
          return const Center(child: Text('Please login again'));
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('items')
              .where('seller_uid', isEqualTo: session.sellerId)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }

            final docs = snapshot.data?.docs ?? [];
            if (docs.isEmpty) {
              return const Center(
                child: Text(
                  'No items listed yet',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final item = docs[index].data();
                final docId = docs[index].id;
                final mediaItems = mediaItemsFromMap(item);
                final firstMedia = mediaItems.isNotEmpty
                    ? mediaItems.first
                    : null;

                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              ItemDetailPage(itemData: item, itemId: docId),
                        ),
                      );
                    },
                    child: Stack(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(0, 0, 10, 0),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: const BorderRadius.horizontal(
                                  left: Radius.circular(12),
                                ),
                                child: firstMedia == null
                                    ? Container(
                                        width: 112,
                                        height: 112,
                                        color: const Color(0xFFDCF8C6),
                                        child: const Icon(
                                          Icons.image,
                                          color: Color(0xFF075E54),
                                        ),
                                      )
                                    : firstMedia.isVideo
                                    ? Container(
                                        width: 112,
                                        height: 112,
                                        color: Colors.black87,
                                        child: const Icon(
                                          Icons.play_circle_fill,
                                          color: Colors.white,
                                        ),
                                      )
                                    : CachedNetworkImage(
                                        imageUrl: firstMedia.url,
                                        width: 112,
                                        height: 112,
                                        fit: BoxFit.cover,
                                        placeholder: (context, url) =>
                                            Container(
                                              width: 112,
                                              height: 112,
                                              color: const Color(0xFFEFF4F1),
                                            ),
                                        errorWidget: (context, url, error) =>
                                            Container(
                                              width: 112,
                                              height: 112,
                                              color: const Color(0xFFDCF8C6),
                                              child: const Icon(
                                                Icons.broken_image,
                                              ),
                                            ),
                                      ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: SizedBox(
                                  height: 112,
                                  child: Column(
                                    children: [
                                      Expanded(
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 8,
                                                    ),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                            Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 2,
                                                  ),
                                              child: Text(
                                                item['item_name'] ?? 'No name',
                                                style: const TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 2,
                                                  ),
                                              child: PriceWithCurrency(
                                                price: _listingPrice(
                                                  item['item_price'],
                                                ),
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey[600],
                                                ),
                                              ),
                                            ),
                                          ],
                                                ),
                                              ),
                                            ),
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.end,
                                              children: [
                                                TextButton(
                                          onPressed: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => ItemEditPage(
                                                  docId: docId,
                                                  itemData: item,
                                                ),
                                              ),
                                            );
                                          },
                                          style: TextButton.styleFrom(
                                            foregroundColor: Colors.blue,
                                            padding: EdgeInsets.zero,
                                            minimumSize: const Size(54, 30),
                                            tapTargetSize: MaterialTapTargetSize
                                                .shrinkWrap,
                                            alignment: Alignment.centerRight,
                                          ),
                                          child: const Text(
                                            'Edit',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                                TextButton(
                                          onPressed: () async {
                                            final confirm =
                                                await showDialog<bool>(
                                                  context: context,
                                                  builder: (context) => Dialog(
                                                    insetPadding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 36,
                                                        ),
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            6,
                                                          ),
                                                    ),
                                                    child: Column(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        const Padding(
                                                          padding:
                                                              EdgeInsets.symmetric(
                                                                vertical: 22,
                                                              ),
                                                          child: Text(
                                                            'Delete !',
                                                            style: TextStyle(
                                                              fontSize: 24,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w500,
                                                            ),
                                                          ),
                                                        ),
                                                        const Divider(
                                                          height: 1,
                                                        ),
                                                        SizedBox(
                                                          height: 58,
                                                          child: Row(
                                                            children: [
                                                              Expanded(
                                                                child: TextButton(
                                                                  onPressed: () =>
                                                                      Navigator.pop(
                                                                        context,
                                                                        false,
                                                                      ),
                                                                  style: TextButton.styleFrom(
                                                                    foregroundColor:
                                                                        Colors
                                                                            .black,
                                                                    shape:
                                                                        const RoundedRectangleBorder(),
                                                                  ),
                                                                  child:
                                                                      const Text(
                                                                        'No',
                                                                        style: TextStyle(
                                                                          fontSize:
                                                                              18,
                                                                          fontWeight:
                                                                              FontWeight.w700,
                                                                        ),
                                                                      ),
                                                                ),
                                                              ),
                                                              const VerticalDivider(
                                                                width: 1,
                                                              ),
                                                              Expanded(
                                                                child: TextButton(
                                                                  onPressed: () =>
                                                                      Navigator.pop(
                                                                        context,
                                                                        true,
                                                                      ),
                                                                  style: TextButton.styleFrom(
                                                                    foregroundColor:
                                                                        Colors
                                                                            .red,
                                                                    shape:
                                                                        const RoundedRectangleBorder(),
                                                                  ),
                                                                  child:
                                                                      const Text(
                                                                        'Yes',
                                                                        style: TextStyle(
                                                                          fontSize:
                                                                              18,
                                                                          fontWeight:
                                                                              FontWeight.w700,
                                                                          color:
                                                                              Colors.red,
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
                                            if (confirm == true &&
                                                context.mounted) {
                                              await _deleteItem(
                                                context,
                                                docId,
                                                item,
                                              );
                                            }
                                          },
                                          style: TextButton.styleFrom(
                                            foregroundColor: Colors.red,
                                            padding: EdgeInsets.zero,
                                            minimumSize: const Size(54, 30),
                                            tapTargetSize: MaterialTapTargetSize
                                                .shrinkWrap,
                                            alignment: Alignment.centerRight,
                                          ),
                                          child: const Text(
                                            'Delete',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 4,
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                _postedDateTime(
                                                  item['created_at'],
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.grey[700],
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              _expiryText(item),
                                              textAlign: TextAlign.right,
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey[700],
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
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
              },
            );
          },
        );
      },
    );
  }
}
