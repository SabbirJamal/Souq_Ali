import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:sms_autofill/sms_autofill.dart';
import 'package:url_launcher/url_launcher.dart';

import 'seller_tabs/seller_add_item_tab.dart';
import 'seller_tabs/seller_feed_tab.dart';
import 'seller_tabs/seller_listings_tab.dart';
import 'seller_tabs/seller_live_tab.dart';
import 'seller_tabs/seller_settings_tab.dart';
import 'seller_session.dart';
import 'seller_session_guard.dart';
import 'upload_status_manager.dart';
import 'utils/network_status.dart';
import 'utils/system_ui_styles.dart';
import 'widgets/app_status_bar.dart';
import 'widgets/app_toast.dart';
import 'widgets/seller_bottom_nav_bar.dart';
import 'widgets/upload_status_banner.dart';

class SellerHomePage extends StatefulWidget {
  const SellerHomePage({
    super.key,
    this.isSellerMode = true,
    this.initialTabIndex = 0,
    this.initialListingsStatus = 'post',
  });

  final bool isSellerMode;
  final int initialTabIndex;
  final String initialListingsStatus;

  @override
  State<SellerHomePage> createState() => _SellerHomePageState();
}

class _SellerHomePageState extends State<SellerHomePage> {
  final _addItemKey = GlobalKey<SellerAddItemTabState>();
  final _feedKey = GlobalKey<SellerFeedTabState>();
  final _liveFeedKey = GlobalKey<SellerFeedTabState>();
  final _listingsKey = GlobalKey<SellerListingsTabState>();
  final _chromeVisible = ValueNotifier<bool>(true);
  late final ValueNotifier<int> _activeTabIndex = ValueNotifier<int>(
    widget.initialTabIndex,
  );
  late int _currentIndex = widget.initialTabIndex;
  final int _listingsRefreshTick = 0;
  static SellerListingsTabState? latestListingsState;
  DateTime? _lastFeedBackPress;
  bool _isAddLiveMode = false;
  late final List<Widget?> _pageCache = List<Widget?>.filled(5, null);

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _activeTabIndex.dispose();
    _chromeVisible.dispose();
    super.dispose();
  }

  void _showFeedTab() {
    setState(() {
      _currentIndex = 0;
    });
    _activeTabIndex.value = 0;
    _setChromeVisible(true);
  }

  void _showItemAddedTab(bool isLiveItem) {
    final nextIndex = isLiveItem ? 1 : 0;
    setState(() {
      _currentIndex = nextIndex;
    });
    _activeTabIndex.value = nextIndex;
    _setChromeVisible(true);
  }

  void _handleItemUploadSuccess(bool isLiveItem) {
    if (isLiveItem) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _liveFeedKey.currentState?.reloadItems(forceFresh: true);
        _listingsKey.currentState?.reloadItems();
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _feedKey.currentState?.reloadItems(forceFresh: true);
        _listingsKey.currentState?.reloadItems();
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
    _activeTabIndex.value = 4;
  }

  void _handleInvalidSellerSession() {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const SellerHomePage(isSellerMode: false),
      ),
      (route) => false,
    );
  }

  void _showSellerGate() {
    setState(() {
      _currentIndex = 4;
    });
    _activeTabIndex.value = 4;
    _setChromeVisible(true);
  }

  Future<void> _onTabTapped(int index) async {
    if (index != 2) {
      _addItemKey.currentState?.closeEmbeddedCamera();
    }

    if (index == 0 && _currentIndex == 0) {
      await _feedKey.currentState?.scrollToTopOrRefresh();
      _setChromeVisible(true);
      return;
    }

    if (index == 1 && _currentIndex == 1) {
      await _liveFeedKey.currentState?.scrollToTopOrRefresh();
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
        if (!await SellerSessionGuard.ensureActive(
          context,
          onInvalid: _handleInvalidSellerSession,
        )) {
          return;
        }
        _showSettingsTab();
        _setChromeVisible(true);
      } else {
        _showSellerGate();
      }
      return;
    }

    if (widget.isSellerMode && (index == 2 || index == 3)) {
      if (!await SellerSessionGuard.ensureActive(
        context,
        onInvalid: _handleInvalidSellerSession,
      )) {
        return;
      }
    }

    if (index == 2 && widget.isSellerMode) {
      if (_pageCache[2] == null) {
        setState(() => _pageCache[2] = _buildPageAt(2));
        await WidgetsBinding.instance.endOfFrame;
      }
      await _addItemKey.currentState?.openMediaFromBottomNav();
      if (!mounted) return;
      setState(() => _currentIndex = 2);
      _activeTabIndex.value = 2;
      _setChromeVisible(true);
      return;
    }

    setState(() {
      _currentIndex = index;
    });
    _activeTabIndex.value = index;
    _setChromeVisible(true);
  }

  Future<void> _logout() async {
    await SellerSession.clear();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const SellerHomePage(isSellerMode: false),
      ),
      (route) => false,
    );
  }

  Future<bool> _deleteAccount() async {
    final session = await SellerSession.current();
    if (session == null) {
      if (!mounted) return false;
      AppToast.show(context, 'Please login again');
      return false;
    }

    if (!await NetworkStatus.hasConnection()) {
      if (!mounted) return false;
      AppToast.show(context, NetworkStatus.noInternetMessage);
      return false;
    }

    try {
      await FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('deleteSellerAccount').call({
        'sellerUid': session.sellerId,
        'sessionId': session.sessionId,
        'deviceId': session.deviceId,
      });
      await SellerSession.clear();
      if (!mounted) return true;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const SellerHomePage(isSellerMode: false),
        ),
        (route) => false,
      );
      AppToast.show(context, 'Account deleted');
      return true;
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return false;
      AppToast.show(
        context,
        error.message ?? 'Could not delete account. Please try again.',
      );
      return false;
    } catch (error) {
      if (!mounted) return false;
      AppToast.show(
        context,
        NetworkStatus.isOfflineError(error)
            ? NetworkStatus.noInternetMessage
            : 'Could not delete account. Please try again.',
      );
      return false;
    }
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
    _setChromeVisible(true);
    AppToast.show(context, 'Please click back again to exit');
  }

  Widget _buildPageAt(int index) {
    return switch (index) {
      0 => SellerFeedTab(
        key: _feedKey,
        chromeVisibleListenable: _chromeVisible,
        activeTabListenable: _activeTabIndex,
        tabIndex: 0,
        onSearchActiveChanged: (isActive) {
          if (isActive) {
            _setChromeVisible(true);
          }
        },
      ),
      1 => SellerLiveTab(
        feedKey: _liveFeedKey,
        chromeVisibleListenable: _chromeVisible,
        activeTabListenable: _activeTabIndex,
        onSearchActiveChanged: (isActive) {
          if (isActive) {
            _setChromeVisible(true);
          }
        },
      ),
      2 =>
        widget.isSellerMode
            ? SellerAddItemTab(
                key: _addItemKey,
                onItemAddedDone: _showItemAddedTab,
                onItemUploadSuccess: _handleItemUploadSuccess,
                onLiveModeChanged: _handleAddLiveModeChanged,
                onSessionInvalid: _handleInvalidSellerSession,
              )
            : const _SellerAccessPrompt(),
      3 =>
        widget.isSellerMode
            ? SellerListingsTab(
                key: _listingsKey,
                refreshTick: _listingsRefreshTick,
                initialStatus: widget.initialListingsStatus,
                onReady: (state) => latestListingsState = state,
                onSessionInvalid: _handleInvalidSellerSession,
              )
            : const _SellerAccessPrompt(),
      4 =>
        widget.isSellerMode
            ? SellerSettingsTab(
                onLogout: _confirmLogout,
                activeTabListenable: _activeTabIndex,
              )
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

  UploadStatusTarget? _currentUploadStatusTarget() {
    return switch (_currentIndex) {
      0 => UploadStatusTarget.feed,
      1 => UploadStatusTarget.live,
      3 => UploadStatusTarget.listings,
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final showTabHeader = widget.isSellerMode && _currentIndex == 4;
    const bottomBarColor = Color(0xFFF4FBF7);
    final statusBarHeight = AppStatusBar.heightOf(context);

    final uploadStatusTarget = _currentUploadStatusTarget();
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppSystemUi.normalStyle,
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
          body: Stack(
            children: [
              Column(
                children: [
                  SizedBox(height: statusBarHeight),
                  if (showTabHeader)
                    _SellerTabHeader(
                      rightAction: _HeaderLogoutButton(
                        onLogout: _confirmLogout,
                        onDeleteAccount: _deleteAccount,
                      ),
                    ),
                  Expanded(
                    child: NotificationListener<ScrollNotification>(
                      onNotification: _onScrollNotification,
                      child: IndexedStack(
                        index: _currentIndex,
                        children: List.generate(5, (index) {
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
                        }),
                      ),
                    ),
                  ),
                ],
              ),
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: AppStatusBar(),
              ),
              if (uploadStatusTarget != null)
                Positioned(
                  top: 62,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: UploadStatusBanner(target: uploadStatusTarget),
                  ),
                ),
            ],
          ),
          bottomNavigationBar: SellerBottomNavBar(
            currentIndex: _currentIndex,
            backgroundColor: bottomBarColor,
            onTap: _onTabTapped,
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
  static const _otpLength = 4;

  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  bool _acceptedTerms = true;
  bool _isLoggingIn = false;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final phoneNumber = _omanPhoneNumber(_phoneController.text);
    setState(() => _isLoggingIn = true);

    final sent = await _requestOtp(phoneNumber);
    if (!mounted) {
      return;
    }
    setState(() => _isLoggingIn = false);

    if (sent && mounted) {
      await _showOtpDialog(phoneNumber);
    }
  }

  Future<bool> _requestOtp(String phoneNumber) async {
    try {
      final appHash = await _androidSmsAppHash();
      final payload = <String, dynamic>{'phoneNumber': phoneNumber};
      if (appHash.isNotEmpty) {
        payload['appHash'] = appHash;
      }
      await FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('sendOtp').call(payload);
      _showMessage('OTP sent');
      return true;
    } catch (error) {
      _showMessage(
        NetworkStatus.isOfflineError(error)
            ? NetworkStatus.noInternetMessage
            : 'Could not send OTP. Please try again.',
      );
      return false;
    }
  }

  Future<String> _androidSmsAppHash() async {
    try {
      return (await SmsAutoFill().getAppSignature).trim();
    } catch (_) {
      return '';
    }
  }

  Future<void> _showOtpDialog(String phoneNumber) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _OtpLoginDialog(
        phoneNumber: phoneNumber,
        onResend: () => _requestOtp(phoneNumber),
        onLogin: (code) => _verifyOtpAndLogin(phoneNumber, code),
      ),
    );
  }

  Future<bool> _verifyOtpAndLogin(String phoneNumber, String code) async {
    if (!_formKey.currentState!.validate()) {
      return false;
    }

    final otpCode = _localDigits(code);
    if (otpCode.length != _otpLength) {
      _showMessage('Enter OTP');
      return false;
    }

    try {
      final result = await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('verifyOtp')
          .call({'phoneNumber': phoneNumber, 'code': otpCode});
      final data = result.data;
      final success = data is Map && data['success'] == true;
      if (!success) {
        _showMessage('Invalid OTP');
        return false;
      }
      return _completeLogin(phoneNumber);
    } catch (error) {
      _showMessage(
        NetworkStatus.isOfflineError(error)
            ? NetworkStatus.noInternetMessage
            : 'Could not verify OTP. Please try again.',
      );
      return false;
    }
  }

  Future<bool> _completeLogin(String phoneNumber) async {
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
          'status': 'active',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        seller = {'name': ''};
      }

      final sellerStatus = seller['status']?.toString().trim().toLowerCase();
      if (sellerStatus == 'suspended' || sellerStatus == 'blocked') {
        if (mounted) {
          await SellerSessionGuard.showBlockedAccountDialog(context);
        }
        return false;
      }

      final session = await SellerSession.save(
        sellerId: phoneNumber,
        name: seller['name']?.toString() ?? '',
        phoneNumber: phoneNumber,
      );
      await SellerSessionGuard.writeActiveSession(session);

      if (!mounted) {
        return false;
      }
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => SellerHomePage(initialTabIndex: isNewSeller ? 4 : 0),
        ),
        (route) => false,
      );
      return true;
    } on FirebaseException catch (error) {
      _showMessage(
        NetworkStatus.isOfflineError(error)
            ? NetworkStatus.noInternetMessage
            : 'Error: ${error.message ?? error.code}',
      );
    } catch (error) {
      _showMessage(
        NetworkStatus.isOfflineError(error)
            ? NetworkStatus.noInternetMessage
            : 'Error: $error',
      );
    }
    return false;
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    AppToast.show(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final isBusy = _isLoggingIn;
    final canContinue = _acceptedTerms && !isBusy;
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
                  child: Image.asset(
                    'assets/branding/logo.png',
                    width: 240,
                    height: 100,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.storefront,
                      size: 82,
                      color: Color(0xFFFF7801),
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
                          Text('🇴🇲', style: TextStyle(fontSize: 20)),
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
              InkWell(
                onTap: () => setState(() => _acceptedTerms = !_acceptedTerms),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(
                        _acceptedTerms
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        color: _acceptedTerms
                            ? const Color(0xFFFF7801)
                            : Colors.grey,
                        size: 24,
                      ),
                      const SizedBox(width: 2),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        alignment: WrapAlignment.center,
                        children: [
                          const Text(
                            'Agree with ',
                            style: TextStyle(fontSize: 14),
                          ),
                          TextButton(
                            onPressed: () {
                              launchUrl(
                                Uri.parse(
                                  'https://bizsooq.com/terms-and-conditions',
                                ),
                                mode: LaunchMode.externalApplication,
                              );
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF0A84FF),
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text(
                              'Terms and Conditions',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: canContinue ? _sendOtp : null,
                icon: isBusy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.login),
                label: Text(isBusy ? 'Please wait...' : 'Get OTP'),
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

class _OtpLoginDialog extends StatefulWidget {
  const _OtpLoginDialog({
    required this.phoneNumber,
    required this.onResend,
    required this.onLogin,
  });

  final String phoneNumber;
  final Future<bool> Function() onResend;
  final Future<bool> Function(String code) onLogin;

  @override
  State<_OtpLoginDialog> createState() => _OtpLoginDialogState();
}

class _OtpLoginDialogState extends State<_OtpLoginDialog> with CodeAutoFill {
  static const _resendSeconds = 30;
  static const _otpLength = _SellerAccessPromptState._otpLength;

  final _controllers = List.generate(
    _otpLength,
    (_) => TextEditingController(),
    growable: false,
  );
  final _focusNodes = List.generate(
    _otpLength,
    (_) => FocusNode(),
    growable: false,
  );

  Timer? _timer;
  int _remainingSeconds = _resendSeconds;
  bool _isResending = false;
  bool _isVerifying = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
    listenForCode();
  }

  @override
  void dispose() {
    cancel();
    _timer?.cancel();
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _remainingSeconds = _resendSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_remainingSeconds <= 1) {
        timer.cancel();
        setState(() => _remainingSeconds = 0);
        return;
      }
      setState(() => _remainingSeconds--);
    });
  }

  String get _code => _controllers.map((c) => c.text).join();

  @override
  void codeUpdated() {
    final otp = _localDigits(code);
    if (otp.length < _controllers.length) {
      return;
    }
    _applyOtpInput(0, otp.substring(0, _controllers.length));
  }

  Future<void> _resendOtp() async {
    if (_remainingSeconds > 0 || _isResending || _isVerifying) {
      return;
    }
    setState(() => _isResending = true);
    final sent = await widget.onResend();
    if (!mounted) {
      return;
    }
    setState(() => _isResending = false);
    if (sent) {
      for (final controller in _controllers) {
        controller.clear();
      }
      _focusNodes.first.requestFocus();
      _startTimer();
    }
  }

  Future<void> _login() async {
    if (_code.length != _otpLength || _isVerifying || _isResending) {
      return;
    }
    setState(() => _isVerifying = true);
    final success = await widget.onLogin(_code);
    if (!mounted) {
      return;
    }
    setState(() => _isVerifying = false);
    if (!success) {
      return;
    }
  }

  void _applyOtpInput(int index, String value) {
    final digits = _localDigits(value);
    if (digits.isEmpty) {
      if (_controllers[index].text.isNotEmpty) {
        _controllers[index].clear();
      }
      setState(() {});
      return;
    }

    var nextIndex = index;
    for (var i = 0; i < digits.length && index + i < _controllers.length; i++) {
      final targetIndex = index + i;
      final digit = digits[i];
      final controller = _controllers[targetIndex];
      if (controller.text != digit) {
        controller.text = digit;
      }
      controller.selection = const TextSelection.collapsed(offset: 1);
      nextIndex = targetIndex;
    }

    if (nextIndex < _focusNodes.length - 1) {
      _focusNodes[nextIndex + 1].requestFocus();
    } else {
      _focusNodes[nextIndex].unfocus();
    }
    setState(() {});
  }

  void _onDigitChanged(int index, String value) {
    _applyOtpInput(index, value);
  }

  @override
  Widget build(BuildContext context) {
    final canLogin =
        _code.length == _otpLength && !_isVerifying && !_isResending;
    final canResend = _remainingSeconds == 0 && !_isResending && !_isVerifying;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: _isVerifying ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ),
              const Text(
                'Enter OTP',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              Text(
                'Code sent to ${widget.phoneNumber}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Colors.black54),
              ),
              const SizedBox(height: 16),
              AutofillGroup(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_controllers.length, (index) {
                    return Padding(
                      padding: EdgeInsets.only(
                        left: index == 0 ? 0 : 6,
                        right: index == _controllers.length - 1 ? 0 : 6,
                      ),
                      child: SizedBox(
                        width: 44,
                        height: 48,
                        child: TextField(
                          controller: _controllers[index],
                          focusNode: _focusNodes[index],
                          enabled: !_isVerifying && !_isResending,
                          autofocus: index == 0,
                          autofillHints: index == 0
                              ? const [AutofillHints.oneTimeCode]
                              : null,
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number,
                          textInputAction: index == _controllers.length - 1
                              ? TextInputAction.done
                              : TextInputAction.next,
                          maxLength: _otpLength,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                          decoration: InputDecoration(
                            counterText: '',
                            filled: true,
                            fillColor: const Color(0xFFF3F3F3),
                            contentPadding: EdgeInsets.zero,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          onChanged: (value) => _onDigitChanged(index, value),
                          onSubmitted: (_) {
                            if (_code.length == _otpLength) {
                              _login();
                            }
                          },
                        ),
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                "Didn't receive code?",
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
              TextButton(
                onPressed: canResend ? _resendOtp : null,
                child: Text(
                  _isResending
                      ? 'Requesting...'
                      : _remainingSeconds > 0
                      ? 'Request Again (00:${_remainingSeconds.toString().padLeft(2, '0')})'
                      : 'Request Again',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: canResend ? const Color(0xFFFF7801) : Colors.grey,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: canLogin ? _login : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFF7801),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                  ),
                  child: _isVerifying
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'LOGIN',
                          style: TextStyle(fontWeight: FontWeight.w800),
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
  const _SellerTabHeader({required this.rightAction});

  final Widget rightAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      width: double.infinity,
      color: const Color(0xFFF4FBF7),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Stack(
        alignment: Alignment.center,
        children: [
          const SizedBox(
            height: 44,
            width: 152,
            child: Image(
              image: AssetImage('assets/branding/logo.png'),
              fit: BoxFit.contain,
            ),
          ),
          Positioned(right: 0, child: rightAction),
        ],
      ),
    );
  }
}

void refreshLatestListingsPage() {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _SellerHomePageState.latestListingsState?.reloadItems();
  });
}

class _HeaderLogoutButton extends StatelessWidget {
  const _HeaderLogoutButton({
    required this.onLogout,
    required this.onDeleteAccount,
  });

  final VoidCallback onLogout;
  final Future<bool> Function() onDeleteAccount;

  Future<void> _showDeleteAccountDialog(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        var isDeleting = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> confirmDelete() async {
              setDialogState(() => isDeleting = true);
              final deleted = await onDeleteAccount();
              if (!deleted && dialogContext.mounted) {
                setDialogState(() => isDeleting = false);
              }
            }

            return Dialog(
              insetPadding: const EdgeInsets.symmetric(horizontal: 36),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 22, 20, 10),
                    child: Text(
                      'DELETE ACCOUNT',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(24, 0, 24, 22),
                    child: Text(
                      'Are you sure you want to delete this account ?',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  SizedBox(
                    height: 58,
                    child: Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: isDeleting
                                ? null
                                : () => Navigator.pop(dialogContext),
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
                            onPressed: isDeleting ? null : confirmDelete,
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.red,
                              shape: const RoundedRectangleBorder(),
                            ),
                            child: isDeleting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text(
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
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: '',
      onSelected: (value) {
        if (value == 'logout') {
          onLogout();
        } else if (value == 'delete_account') {
          _showDeleteAccountDialog(context);
        }
      },
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      itemBuilder: (context) => const [
        PopupMenuItem<String>(
          value: 'logout',
          child: Text(
            'LOG OUT',
            style: TextStyle(color: Colors.red, fontWeight: FontWeight.w700),
          ),
        ),
        PopupMenuItem<String>(
          value: 'delete_account',
          child: Text(
            'DELETE ACCOUNT',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.w700),
          ),
        ),
      ],
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: const Color(0xFFFF7801),
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: const Icon(Icons.settings, color: Colors.white, size: 22),
      ),
    );
  }
}
