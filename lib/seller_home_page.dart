import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'seller_tabs/seller_add_item_tab.dart';
import 'seller_tabs/seller_feed_tab.dart';
import 'seller_tabs/seller_listings_tab.dart';
import 'seller_tabs/seller_live_tab.dart';
import 'seller_tabs/seller_settings_tab.dart';
import 'seller_session.dart';
import 'seller_session_guard.dart';
import 'widgets/app_toast.dart';

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
  final _liveFeedKey = GlobalKey<SellerFeedTabState>();
  final _listingsKey = GlobalKey<SellerListingsTabState>();
  final _chromeVisible = ValueNotifier<bool>(true);
  late int _currentIndex = widget.initialTabIndex;
  int _feedRefreshTick = 0;
  int _listingsRefreshTick = 0;
  DateTime? _lastFeedBackPress;
  bool _isAddLiveMode = false;
  late final List<Widget?> _pageCache = List<Widget?>.filled(5, null);

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
    });
    _setChromeVisible(true);
  }

  void _handleItemUploadSuccess(bool isLiveItem) {
    if (isLiveItem) {
      setState(() => _currentIndex = 1);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _liveFeedKey.currentState?.mergeLatestItems();
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _feedKey.currentState?.mergeLatestItems();
      });
    }
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

  void _handleInvalidSellerSession() {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const SellerHomePage(isSellerMode: false)),
      (route) => false,
    );
  }

  void _showSellerGate() {
    setState(() {
      _currentIndex = 4;
    });
    _setChromeVisible(true);
  }

  Future<void> _onTabTapped(int index) async {
    if (index == 0 && _currentIndex == 0) {
      _feedKey.currentState?.scrollToTop();
      _setChromeVisible(true);
      return;
    }

    if (index == 3 && _currentIndex == 3) {
      _listingsKey.currentState?.scrollToTopOrRefresh();
      _setChromeVisible(true);
      return;
    }

    if (index == 4) {
      if (widget.isSellerMode) {
        if (!await SellerSessionGuard.ensureActive(context, onInvalid: _handleInvalidSellerSession)) return;
        _showSettingsTab();
        _setChromeVisible(true);
      } else {
        _showSellerGate();
      }
      return;
    }

    if (widget.isSellerMode && (index == 2 || index == 3)) {
      if (!await SellerSessionGuard.ensureActive(context, onInvalid: _handleInvalidSellerSession)) return;
    }

    setState(() {
      _currentIndex = index;
      if (index == 3 && widget.isSellerMode) {
        _listingsRefreshTick++;
        _pageCache[3] = null;
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
    AppToast.show(context, 'Please click back again to exit');
  }

  Widget _buildPageAt(int index) {
    return switch (index) {
      0 => SellerFeedTab(
        key: _feedKey,
        chromeVisibleListenable: _chromeVisible,
        onSearchActiveChanged: (isActive) {
          if (isActive) {
            _setChromeVisible(true);
          }
        },
      ),
      1 => SellerLiveTab(feedKey: _liveFeedKey),
      2 => widget.isSellerMode
          ? SellerAddItemTab(
              key: _addItemKey,
              onItemAddedDone: _showItemAddedTab,
              onItemUploadSuccess: _handleItemUploadSuccess,
              onLiveModeChanged: _handleAddLiveModeChanged,
              onSessionInvalid: _handleInvalidSellerSession,
            )
          : const _SellerAccessPrompt(),
      3 => widget.isSellerMode
          ? SellerListingsTab(key: _listingsKey, refreshTick: _listingsRefreshTick, onSessionInvalid: _handleInvalidSellerSession)
          : const _SellerAccessPrompt(),
      4 => widget.isSellerMode
          ? SellerSettingsTab(onLogout: _confirmLogout)
          : const _SellerAccessPrompt(),
      _ => const SizedBox.shrink(),
    };
  }

  Widget _pageAt(int index) {
    return _pageCache[index] ??= _buildPageAt(index);
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
    final showTabHeader = widget.isSellerMode && _currentIndex == 4;
    final bottomBarColor = _currentIndex == 2 && _isAddLiveMode
        ? const Color(0xFFFFE9EC)
        : const Color(0xFFF4FBF7);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: bottomBarColor,
        systemNavigationBarIconBrightness: Brightness.dark,
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
          extendBody: true, // Background flows behind navigation bar
          body: Column(
            children: [
              // Efficiently handles the status bar height with the brand color
              Container(
                height: MediaQuery.viewPaddingOf(context).top,
                color: Colors.black,
              ),
              if (showTabHeader)
                _SellerTabHeader(
                  rightAction: _HeaderLogoutButton(onLogout: _confirmLogout),
                ),
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: _onScrollNotification,
                  child: IndexedStack(
                    index: _currentIndex,
                    children: List.generate(
                      5,
                      (index) {
                        // Only build the page if it's currently selected or was previously cached
                        final isPageInitialized = _pageCache[index] != null;
                        final isCurrentPage = index == _currentIndex;
                        
                        if (isCurrentPage || isPageInitialized) {
                          return TickerMode(
                            enabled: isCurrentPage,
                            child: _pageAt(index),
                          );
                        }
                        
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
          bottomNavigationBar: ColoredBox(
            color: bottomBarColor,
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewPaddingOf(context).bottom,
              ),
              child: SizedBox(
                height: 48,
                child: Row(
                  children: [
                    _buildTabItem(0, Icons.home, 33, 'Home'),
                    _buildTabItem(1, null, 29, 'Live'),
                    _buildTabItem(2, Icons.add_circle_outline, 29, 'Add'),
                    _buildTabItem(3, Icons.person, 29, 'Listings'),
                    _buildTabItem(4, Icons.settings, 29, 'Settings'),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabItem(int index, IconData? icon, double size, String label) {
    final isSelected = _currentIndex == index;
    return Expanded(
      child: Center(
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkResponse(
            onTap: () => _onTabTapped(index),
            containedInkWell: true,
            customBorder: const CircleBorder(),
            radius: 52,
            splashColor: Colors.black12,
            highlightColor: Colors.black12,
            child: SizedBox(
              width: 108,
              height: 48,
              child: Center(
                child: icon == null
                    ? const Text(
                        'LIVE',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFFFF0000),
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                      )
                    : Icon(
                        icon,
                        size: size,
                        color: isSelected ? const Color(0xFFFF7801) : Colors.grey,
                      ),
              ),
            ),
          ),
        ),
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

      final session = await SellerSession.save(
        sellerId: phoneNumber,
        name: seller['name']?.toString() ?? '',
        phoneNumber: phoneNumber,
      );
      await SellerSessionGuard.writeActiveSession(session);

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
    AppToast.show(context, message);
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
                  style: const TextStyle(fontSize: 16),
                  keyboardType: TextInputType.number,
                  maxLength: 8,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    prefixIcon: Padding(
                      padding: EdgeInsets.only(left: 12, right: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.phone),
                          SizedBox(width: 8),
                          Text('+968 ', style: TextStyle(fontSize: 16)),
                        ],
                      ),
                    ),
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

