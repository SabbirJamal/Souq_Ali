import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'seller_feed_tab.dart';

class SellerLiveTab extends StatelessWidget {
  const SellerLiveTab({
    super.key,
    this.feedKey,
    this.chromeVisibleListenable,
    this.activeTabListenable,
    this.gridLayoutMode,
    required this.onSearchActiveChanged,
  });

  final GlobalKey<SellerFeedTabState>? feedKey;
  final ValueListenable<bool>? chromeVisibleListenable;
  final ValueListenable<int>? activeTabListenable;
  final ValueNotifier<bool>? gridLayoutMode;
  final ValueChanged<bool> onSearchActiveChanged;

  @override
  Widget build(BuildContext context) {
    return SellerFeedTab(
      key: feedKey,
      chromeVisibleListenable: chromeVisibleListenable,
      activeTabListenable: activeTabListenable,
      tabIndex: 1,
      gridLayoutMode: gridLayoutMode,
      onSearchActiveChanged: onSearchActiveChanged,
      itemStatus: 'live',
      emptyMessage: 'No live items available',
    );
  }
}
