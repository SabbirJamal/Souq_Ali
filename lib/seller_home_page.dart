import 'package:flutter/material.dart';

import 'seller_tabs/seller_add_item_tab.dart';
import 'seller_tabs/seller_feed_tab.dart';
import 'seller_tabs/seller_listings_tab.dart';
import 'seller_tabs/seller_settings_tab.dart';

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
    SellerAddItemTab(key: _addItemKey, onItemAddedDone: _showFeedTab),
    const SellerListingsTab(),
    const SellerSettingsTab(),
  ];

  void _showFeedTab() {
    setState(() => _currentIndex = 0);
  }

  void _onTabTapped(int index) {
    setState(() => _currentIndex = index);

    if (index == 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _addItemKey.currentState?.openMediaSheet();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _currentIndex == 0
          ? null
          : AppBar(
              title: const Text('SOOQ ALI'),
              backgroundColor: const Color(0xFF25D366),
              foregroundColor: Colors.white,
            ),
      body: _pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _onTabTapped,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF25D366),
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(
            icon: Icon(Icons.add_circle_outline),
            label: 'Add',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.list_alt),
            label: 'Listings',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
