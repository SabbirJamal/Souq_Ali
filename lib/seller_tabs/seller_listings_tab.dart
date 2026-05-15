import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../item_detail_page.dart';
import '../item_edit_page.dart';
import '../seller_session.dart';
import '../story_repository.dart';
import '../widgets/media_carousel.dart';
import '../widgets/price_with_currency.dart';

class SellerListingsTab extends StatelessWidget {
  const SellerListingsTab({super.key});

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
      future: SellerSession.current(),
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
              padding: const EdgeInsets.all(12),
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
                          padding: const EdgeInsets.fromLTRB(6, 4, 10, 8),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: firstMedia == null
                                    ? Container(
                                        width: 92,
                                        height: 96,
                                        color: const Color(0xFFDCF8C6),
                                        child: const Icon(
                                          Icons.image,
                                          color: Color(0xFF075E54),
                                        ),
                                      )
                                    : firstMedia.isVideo
                                    ? Container(
                                        width: 92,
                                        height: 96,
                                        color: Colors.black87,
                                        child: const Icon(
                                          Icons.play_circle_fill,
                                          color: Colors.white,
                                        ),
                                      )
                                    : CachedNetworkImage(
                                        imageUrl: firstMedia.url,
                                        width: 92,
                                        height: 96,
                                        fit: BoxFit.cover,
                                        placeholder: (context, url) =>
                                            Container(
                                              width: 92,
                                              height: 96,
                                              color: const Color(0xFFEFF4F1),
                                            ),
                                        errorWidget: (context, url, error) =>
                                            Container(
                                              width: 92,
                                              height: 96,
                                              color: const Color(0xFFDCF8C6),
                                              child: const Icon(
                                                Icons.broken_image,
                                              ),
                                            ),
                                      ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item['item_name'] ?? 'No name',
                                            style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 4),
                                          PriceWithCurrency(
                                            price:
                                                item['item_price']?.toString() ??
                                                '',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              onPressed: () {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (_) =>
                                                        ItemEditPage(
                                                          docId: docId,
                                                          itemData: item,
                                                        ),
                                                  ),
                                                );
                                              },
                                              icon: const Icon(
                                                Icons.edit,
                                                color: Colors.blue,
                                              ),
                                            ),
                                            IconButton(
                                              onPressed: () async {
                                                final confirm =
                                                    await showDialog<bool>(
                                                      context: context,
                                                      builder: (context) =>
                                                          AlertDialog(
                                                            title: const Text(
                                                              'Delete Item',
                                                            ),
                                                            content: const Text(
                                                              'Are you sure you want to delete this item?',
                                                            ),
                                                            actions: [
                                                              TextButton(
                                                                onPressed: () =>
                                                                    Navigator.pop(
                                                                      context,
                                                                      false,
                                                                    ),
                                                                child:
                                                                    const Text(
                                                                      'Cancel',
                                                                    ),
                                                              ),
                                                              TextButton(
                                                                onPressed: () =>
                                                                    Navigator.pop(
                                                                      context,
                                                                      true,
                                                                    ),
                                                                child: const Text(
                                                                  'Delete',
                                                                  style: TextStyle(
                                                                    color: Colors
                                                                        .red,
                                                                  ),
                                                                ),
                                                              ),
                                                            ],
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
                                              icon: const Icon(
                                                Icons.delete,
                                                color: Colors.red,
                                              ),
                                            ),
                                          ],
                                        ),
                                        Text(
                                          _postedDateTime(item['created_at']),
                                          textAlign: TextAlign.right,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey[700],
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
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
