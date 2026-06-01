import 'package:flutter/material.dart';

import 'seller_feed_tab.dart';

class SellerLiveTab extends StatelessWidget {
  const SellerLiveTab({super.key});

  @override
  Widget build(BuildContext context) {
    return SellerFeedTab(
      onSearchActiveChanged: (_) {},
      itemStatus: 'live',
      emptyMessage: 'No live items available',
    );
  }
}
