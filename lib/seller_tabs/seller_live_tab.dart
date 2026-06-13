import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'seller_feed_tab.dart';

class SellerLiveTab extends StatelessWidget {
  const SellerLiveTab({
    super.key,
    this.feedKey,
    this.chromeVisibleListenable,
    required this.onSearchActiveChanged,
  });

  final GlobalKey<SellerFeedTabState>? feedKey;
  final ValueListenable<bool>? chromeVisibleListenable;
  final ValueChanged<bool> onSearchActiveChanged;

  @override
  Widget build(BuildContext context) {
    return SellerFeedTab(
      key: feedKey,
      chromeVisibleListenable: chromeVisibleListenable,
      onSearchActiveChanged: onSearchActiveChanged,
      itemStatus: 'live',
      emptyMessage: 'No live items available',
    );
  }
}
