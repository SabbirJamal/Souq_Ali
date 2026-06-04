import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lottie/lottie.dart';

import 'seller_tabs/seller_add_item_tab.dart';
import 'seller_tabs/seller_feed_tab.dart';
import 'seller_tabs/seller_listings_tab.dart';
import 'seller_tabs/seller_live_tab.dart';
import 'seller_tabs/seller_settings_tab.dart';
import 'seller_session.dart';

class SellerHomePage extends StatefulWidget {
  const SellerHomePage({
    super.key,
    this.isSellerMode = true,
    this.initialTabIndex = 0,
  });

  final bool isSellerMode;
  final int initialTabIndex;

  @override
  State<SellerHomePage> createState() => _SellerHomePageState();
}

class _SellerHomePageState extends State<SellerHomePage> {
  final _addItemKey = GlobalKey<SellerAddItemTabState>();
  final _feedKey = GlobalKey<SellerFeedTabState>();
  final _chromeVisible = ValueNotifier<bool>(true);
  late int _currentIndex = widget.initialTabIndex;
  int _feedRefreshTick = 0;
  int _listingsRefreshTick = 0;
  DateTime? _lastFeedBackPress;
  bool _isFeedSearchActive = false;
  bool _isAddLiveMode = false;

  @override
  void dispose() {
    _chromeVisible.dispose();
    super.dispose();
  }

  void _showFeedTab() {
    setState(() {
      _currentIndex = 0;
      _feedRefreshTick++;
    });
    _setChromeVisible(true);
  }

  void _showItemAddedTab(bool isLiveItem) {
    setState(() {
      _currentIndex = isLiveItem ? 1 : 0;
      if (!isLiveItem) {
        _feedRefreshTick++;
      }
    });
    _setChromeVisible(true);
  }

  void _handleAddLiveModeChanged(bool isLive) {
    if (_isAddLiveMode == isLive) {
      return;
    }
    setState(() => _isAddLiveMode = isLive);
  }

  void _showSettingsTab() {
    setState(() => _currentIndex = 4);
  }

  void _showSellerGate() {
    setState(() {
      _currentIndex = 4;
    });
    _setChromeVisible(true);
  }

  void _onTabTapped(int index) {
    if (index == 0 && _currentIndex == 0) {
      _feedKey.currentState?.scrollToTop();
      _setChromeVisible(true);
      return;
    }

    if (index == 4) {
      if (widget.isSellerMode) {
        _showSettingsTab();
        _setChromeVisible(true);
      } else {
        _showSellerGate();
      }
      return;
    }

    setState(() {
      _currentIndex = index;
      if (index == 3 && widget.isSellerMode) {
        _listingsRefreshTick++;
      }
    });
    _setChromeVisible(true);

    if (index == 2 && widget.isSellerMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _addItemKey.currentState?.openMediaSheet();
      });
    }
  }

  Future<void> _logout() async {
    await SellerSession.clear();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const SellerHomePage(isSellerMode: false)),
      (route) => false,
    );
  }

  Future<void> _confirmLogout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 36),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 22),
              child: Text(
                'Logout !',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w500),
              ),
            ),
            const Divider(height: 1),
            SizedBox(
            height: 64,
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.black,
                        shape: const RoundedRectangleBorder(),
                      ),
                      child: const Text(
                        'No',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.red,
                        shape: const RoundedRectangleBorder(),
                      ),
                      child: const Text(
                        'Yes',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.red,
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

    if (shouldLogout == true) {
      await _logout();
    }
  }

  void _handleBackPressed() {
    if (_currentIndex != 0) {
      _showFeedTab();
      return;
    }

    final now = DateTime.now();
    final canExit =
        _lastFeedBackPress != null &&
        now.difference(_lastFeedBackPress!) < const Duration(seconds: 2);

    if (canExit) {
      SystemNavigator.pop();
      return;
    }

    _lastFeedBackPress = now;
    setState(() => _feedRefreshTick++);
    _setChromeVisible(true);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check, color: Color(0xFF25D366), size: 30),
              SizedBox(width: 18),
              Expanded(
                child: Text(
                  'Please click back again to exit',
                  style: TextStyle(fontSize: 18),
                ),
              ),
            ],
          ),
          backgroundColor: Color(0xFF3A3A3A),
          duration: Duration(seconds: 2),
        ),
      );
  }

  Widget _buildPageAt(int index) {
    return switch (index) {
      0 => SellerFeedTab(
        key: _feedKey,
        chromeVisibleListenable: _chromeVisible,
        onSearchActiveChanged: (isActive) {
          _isFeedSearchActive = isActive;
          if (isActive) {
            _setChromeVisible(true);
          }
        },
      ),
      1 => const SellerLiveTab(),
      2 => widget.isSellerMode
          ? SellerAddItemTab(
              key: _addItemKey,
              onItemAddedDone: _showItemAddedTab,
              onLiveModeChanged: _handleAddLiveModeChanged,
            )
          : const _SellerAccessPrompt(),
      3 => widget.isSellerMode
          ? SellerListingsTab(refreshTick: _listingsRefreshTick)
          : const _SellerAccessPrompt(),
      4 => widget.isSellerMode
          ? SellerSettingsTab(onLogout: _confirmLogout)
          : const _SellerAccessPrompt(),
      _ => const SizedBox.shrink(),
    };
  }

  void _setChromeVisible(bool visible) {
    if (_chromeVisible.value != visible) {
      _chromeVisible.value = visible;
    }
  }

  bool _onScrollNotification(ScrollNotification notification) {
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final showTabHeader = widget.isSellerMode && _currentIndex == 4;
    final bottomBarColor = _currentIndex == 2 && _isAddLiveMode
        ? const Color(0xFFFFE9EC)
        : const Color(0xFFF4FBF7);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.black,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) {
            _handleBackPressed();
          }
        },
        child: Scaffold(
          backgroundColor: const Color(0xFFF4FBF7),
          body: Column(
            children: [
              Container(height: topInset, color: Colors.black),
              if (showTabHeader)
                _SellerTabHeader(
                  rightAction: _HeaderLogoutButton(onLogout: _confirmLogout),
                ),
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: _onScrollNotification,
                  child: IndexedStack(
                    index: _currentIndex,
                    children: List.generate(5, _buildPageAt),
                  ),
                ),
              ),
            ],
          ),
          bottomNavigationBar: ColoredBox(
            color: bottomBarColor,
            child: SizedBox(
              height: 58,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final tabWidth = constraints.maxWidth / 5;
                  const liveIconWidth = 225.0;
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      BottomNavigationBar(
                        currentIndex: _currentIndex > 4 ? 4 : _currentIndex,
                        onTap: _onTabTapped,
                        type: BottomNavigationBarType.fixed,
                        selectedItemColor: const Color(0xFFFF7801),
                        unselectedItemColor: Colors.grey,
                        backgroundColor: bottomBarColor,
                        selectedFontSize: 0,
                        unselectedFontSize: 0,
                        showSelectedLabels: false,
                        showUnselectedLabels: false,
                        iconSize: 24,
                        items: const [
                          BottomNavigationBarItem(
                            icon: Icon(Icons.home, size: 28),
                            label: 'Home',
                          ),
                          BottomNavigationBarItem(
                            icon: SizedBox(width: 24, height: 24),
                            activeIcon: SizedBox(width: 24, height: 24),
                            label: 'Live',
                          ),
                          BottomNavigationBarItem(
                            icon: Icon(Icons.add_circle_outline),
                            label: 'Add',
                          ),
                          BottomNavigationBarItem(
                            icon: Icon(Icons.person),
                            label: 'Listings',
                          ),
                          BottomNavigationBarItem(
                            icon: Icon(Icons.settings),
                            label: 'Settings',
                          ),
                        ],
                      ),
                      Positioned(
                        left: tabWidth + (tabWidth - liveIconWidth) / 2,
                        top: -31,
                        child: const IgnorePointer(child: _LiveNavIcon()),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LiveNavIcon extends StatelessWidget {
  const _LiveNavIcon();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 225,
      height: 108,
      child: Lottie.asset(
        'assets/lottie/live2.json',
        fit: BoxFit.contain,
        repeat: true,
        animate: true,
      ),
    );
  }
}

class _SellerAccessPrompt extends StatefulWidget {
  const _SellerAccessPrompt();

  @override
  State<_SellerAccessPrompt> createState() => _SellerAccessPromptState();
}

class _SellerAccessPromptState extends State<_SellerAccessPrompt> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  bool _isLoggingIn = false;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final phoneNumber = _omanPhoneNumber(_phoneController.text);
    setState(() => _isLoggingIn = true);

    try {
      final sellersRef = FirebaseFirestore.instance.collection('sellers');
      final sellerDoc = await sellersRef.doc(phoneNumber).get();

      var isNewSeller = false;
      var seller = sellerDoc.data();
      if (!sellerDoc.exists || seller == null) {
        isNewSeller = true;
        await sellersRef.doc(phoneNumber).set({
          'uid': phoneNumber,
          'name': '',
          'phoneNumber': phoneNumber,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        seller = {'name': ''};
      }

      await SellerSession.save(
        sellerId: phoneNumber,
        name: seller['name']?.toString() ?? '',
        phoneNumber: phoneNumber,
      );

      if (!mounted) {
        return;
      }
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => SellerHomePage(initialTabIndex: isNewSeller ? 4 : 0),
        ),
        (route) => false,
      );
    } on FirebaseException catch (error) {
      _showMessage('Error: ${error.message ?? error.code}');
    } catch (error) {
      _showMessage('Error: $error');
    } finally {
      if (mounted) {
        setState(() => _isLoggingIn = false);
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Transform.translate(
                  offset: const Offset(0, -28),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: Image.asset(
                      'assets/branding/logo.png',
                      width: 240,
                      height: 100,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Icon(
                        Icons.storefront,
                        size: 82,
                        color: Color(0xFFFF7801),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Form(
                key: _formKey,
                child: TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.number,
                  maxLength: 8,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    prefixText: '+968 ',
                    prefixIcon: Icon(Icons.phone),
                    counterText: '',
                  ),
                  validator: _validatePhoneNumber,
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _isLoggingIn ? null : _login,
                icon: _isLoggingIn
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.login),
                label: Text(_isLoggingIn ? 'Please wait...' : 'Continue'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFF7801),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String? _validatePhoneNumber(String? value) {
  final phone = _localDigits(value);
  if (phone.isEmpty) {
    return 'Enter your phone number';
  }
  if (phone.length != 8) {
    return 'Enter the 8 digit Oman phone number';
  }
  return null;
}

String _omanPhoneNumber(String value) {
  return '+968${_localDigits(value)}';
}

String _localDigits(String? value) {
  return (value ?? '').replaceAll(RegExp(r'[^0-9]'), '');
}

class _SellerTabHeader extends StatelessWidget {
  const _SellerTabHeader({required this.rightAction});

  final Widget rightAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      width: double.infinity,
      color: const Color(0xFFF4FBF7),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Stack(
        alignment: Alignment.center,
        children: [
          const SizedBox(
            height: 56,
            width: 152,
            child: Image(
              image: AssetImage('assets/branding/logo.png'),
              fit: BoxFit.cover,
            ),
          ),
          Positioned(
            right: 0,
            child: rightAction,
          ),
        ],
      ),
    );
  }
}

class _HeaderLogoutButton extends StatelessWidget {
  const _HeaderLogoutButton({required this.onLogout});

  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onLogout,
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFFFF7801),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        minimumSize: const Size(86, 38),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: const Text(
        'Log out',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}

