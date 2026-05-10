import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'seller_tabs/seller_add_item_tab.dart';
import 'seller_tabs/seller_feed_tab.dart';
import 'seller_tabs/seller_listings_tab.dart';
import 'seller_tabs/seller_search_tab.dart';
import 'seller_tabs/seller_settings_tab.dart';
import 'seller_tabs/seller_stories_tab.dart';

class SellerHomePage extends StatefulWidget {
  const SellerHomePage({super.key});

  @override
  State<SellerHomePage> createState() => _SellerHomePageState();
}

class _SellerHomePageState extends State<SellerHomePage> {
  final _addItemKey = GlobalKey<SellerAddItemTabState>();
  int _currentIndex = 0;

  late final List<Widget> _pages = [
    const SellerFeedTab(),
    const SellerStoriesTab(),
    SellerAddItemTab(key: _addItemKey, onItemAddedDone: _showFeedTab),
    const SellerSearchTab(),
    const SellerListingsTab(),
    const SellerSettingsTab(),
  ];

  void _showFeedTab() {
    setState(() => _currentIndex = 0);
  }

  void _onTabTapped(int index) {
    setState(() => _currentIndex = index);

    if (index == 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _addItemKey.currentState?.openMediaSheet();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final showTabHeader = _currentIndex != 0 && _currentIndex != 1;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.black,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        body: Column(
          children: [
            Container(height: topInset, color: Colors.black),
            if (showTabHeader)
              _SellerTabHeader(
                onSettingsTap: () => setState(() => _currentIndex = 5),
              ),
            Expanded(child: _pages[_currentIndex]),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _currentIndex >= 5 ? 4 : _currentIndex,
          onTap: _onTabTapped,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: const Color(0xFF25D366),
          unselectedItemColor: Colors.grey,
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
            BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Search'),
            BottomNavigationBarItem(
              icon: Icon(Icons.list_alt),
              label: 'Listings',
            ),
          ],
        ),
      ),
    );
  }
}

class _SellerTabHeader extends StatelessWidget {
  const _SellerTabHeader({required this.onSettingsTap});

  final VoidCallback onSettingsTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      width: double.infinity,
      color: const Color(0xFFFF7801),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const Text(
            'BIZ SOOQ',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: onSettingsTap,
            icon: const Icon(Icons.settings, color: Colors.white),
            tooltip: 'Settings',
          ),
        ],
      ),
    );
  }
}
