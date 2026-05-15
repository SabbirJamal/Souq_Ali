import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'seller_tabs/seller_add_item_tab.dart';
import 'seller_tabs/seller_feed_tab.dart';
import 'seller_tabs/seller_listings_tab.dart';
import 'seller_tabs/seller_settings_tab.dart';
import 'seller_tabs/seller_stories_tab.dart';
import 'seller_register_page.dart';
import 'seller_session.dart';

class SellerHomePage extends StatefulWidget {
  const SellerHomePage({super.key, this.isSellerMode = true});

  final bool isSellerMode;

  @override
  State<SellerHomePage> createState() => _SellerHomePageState();
}

class _SellerHomePageState extends State<SellerHomePage> {
  final _addItemKey = GlobalKey<SellerAddItemTabState>();
  final _chromeVisible = ValueNotifier<bool>(true);
  int _currentIndex = 0;
  int _feedRefreshTick = 0;
  DateTime? _lastFeedBackPress;

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
    setState(() {
      _currentIndex = index;
    });
    _setChromeVisible(true);

    if (index == 2 && widget.isSellerMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _addItemKey.currentState?.openMediaSheet();
      });
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

  Widget _buildCurrentPage() {
    return switch (_currentIndex) {
      0 => SellerFeedTab(
        key: ValueKey('feed-$_feedRefreshTick'),
        chromeVisibleListenable: _chromeVisible,
      ),
      1 => const SellerStoriesTab(),
      2 => widget.isSellerMode
          ? SellerAddItemTab(key: _addItemKey, onItemAddedDone: _showFeedTab)
          : const _SellerAccessPrompt(),
      3 => widget.isSellerMode
          ? const SellerListingsTab()
          : const _SellerAccessPrompt(),
      _ => widget.isSellerMode
          ? SellerSettingsTab(onBack: _showFeedTab)
          : const _SellerAccessPrompt(),
    };
  }

  void _setChromeVisible(bool visible) {
    if (_chromeVisible.value != visible) {
      _chromeVisible.value = visible;
    }
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (_currentIndex != 0) {
      return false;
    }
    if (notification.metrics.axis != Axis.vertical) {
      return false;
    }
    if (notification is UserScrollNotification) {
      final shouldShow = notification.direction == ScrollDirection.forward;
      final shouldHide = notification.direction == ScrollDirection.reverse;
      if (shouldShow) {
        _setChromeVisible(true);
      } else if (shouldHide) {
        _setChromeVisible(false);
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final showTabHeader =
        widget.isSellerMode &&
        _currentIndex != 0 &&
        _currentIndex != 1 &&
        _currentIndex != 3 &&
        _currentIndex != 4;

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
          body: Column(
            children: [
              Container(height: topInset, color: Colors.black),
              if (showTabHeader)
                const _SellerTabHeader(),
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: _onScrollNotification,
                  child: _buildCurrentPage(),
                ),
              ),
            ],
          ),
          bottomNavigationBar: ClipRect(
            child: ValueListenableBuilder<bool>(
              valueListenable: _chromeVisible,
              builder: (context, visible, child) {
                final shouldShow = _currentIndex != 0 || visible;
                return AnimatedAlign(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.bottomCenter,
                  heightFactor: shouldShow ? 1 : 0,
                  child: child,
                );
              },
              child: BottomNavigationBar(
                currentIndex: _currentIndex,
                onTap: _onTabTapped,
                type: BottomNavigationBarType.fixed,
                selectedItemColor: const Color(0xFFFF7801),
                unselectedItemColor: Colors.grey,
                selectedFontSize: 11,
                unselectedFontSize: 11,
                iconSize: 24,
                items: const [
                  BottomNavigationBarItem(
                    icon: Icon(Icons.home),
                    label: 'Home',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.play_circle_fill),
                    label: 'Stories',
                  ),
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
      final sellerDoc = await FirebaseFirestore.instance
          .collection('sellers')
          .doc(phoneNumber)
          .get();

      final seller = sellerDoc.data();
      if (!sellerDoc.exists || seller == null) {
        _showMessage('Seller account not found. Please register first.');
        return;
      }

      await SellerSession.save(
        sellerId: phoneNumber,
        name: seller['name']?.toString() ?? 'Seller',
        phoneNumber: phoneNumber,
      );

      if (!mounted) {
        return;
      }
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const SellerHomePage()),
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
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Image.asset(
                    'assets/branding/logo.png',
                    width: 92,
                    height: 92,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.storefront,
                      size: 82,
                      color: Color(0xFFFF7801),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 26),
              Form(
                key: _formKey,
                child: TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.number,
                  maxLength: 8,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Phone number',
                    hintText: '90000000',
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
                label: Text(_isLoggingIn ? 'Logging in...' : 'Login'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFF7801),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: 22),
              Divider(color: Colors.grey[350], thickness: 1),
              const SizedBox(height: 8),
              Text(
                'OR',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey[700],
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 28),
              InkWell(
                borderRadius: BorderRadius.circular(28),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const SellerRegisterPage(),
                    ),
                  );
                },
                child: Container(
                  height: 160,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: const Color(0xFFFF7801),
                      width: 1.7,
                    ),
                  ),
                  child: const Text(
                    'Create Account',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 30,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
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
  const _SellerTabHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      width: double.infinity,
      color: const Color(0xFFFF7801),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: const Center(
        child: Text(
            'BIZ SOOQ',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
      ),
    );
  }
}
