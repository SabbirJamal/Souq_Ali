import 'package:flutter/material.dart';

import 'seller_feed_tab.dart';

class SellerLiveTab extends StatelessWidget {
  const SellerLiveTab({super.key, this.feedKey});

  final GlobalKey<SellerFeedTabState>? feedKey;

  @override
  Widget build(BuildContext context) {
    return SellerFeedTab(
      key: feedKey,
      onSearchActiveChanged: (_) {},
      itemStatus: 'live',
      emptyMessage: 'No live items available',
    );
  }
}
