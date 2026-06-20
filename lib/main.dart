import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart' as permissions;
import 'package:url_launcher/url_launcher.dart';

import 'camera_capture_page.dart';
import 'item_detail_page.dart';
import 'seller_home_page.dart';
import 'seller_session.dart';
import 'services/app_update_service.dart';
import 'services/feed_service.dart';
import 'utils/system_ui_styles.dart';

Future<void> main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  AppSystemUi.applyNormal();

  // Parallelize Firebase and Session loading
  final firebaseFuture = Firebase.initializeApp();
  final sessionFuture = SellerSession.current();
  final cameraPrewarmFuture = _prewarmCameraIfPermitted();
  unawaited(_warmInitialFeed(firebaseFuture, sessionFuture));

  runApp(SouqaliApp(
    firebaseFuture: firebaseFuture,
    sessionFuture: sessionFuture,
    cameraPrewarmFuture: cameraPrewarmFuture,
  ));
}

Future<void> _prewarmCameraIfPermitted() async {
  final camera = await permissions.Permission.camera.status;
  final microphone = await permissions.Permission.microphone.status;
  if (!camera.isGranted || !microphone.isGranted) return;

  try {
    await CameraCapturePage.preloadCameras();
  } catch (_) {
    // Camera warm-up is opportunistic; normal camera open handles failures.
  }
}

Future<void> _warmInitialFeed(
  Future<void> firebaseFuture,
  Future<SellerSession?> sessionFuture,
) async {
  try {
    await firebaseFuture;
    final session = await sessionFuture;
    String? viewerId = session?.sellerId.trim();
    if (viewerId == null || viewerId.isEmpty) {
      final auth = FirebaseAuth.instance;
      final user = auth.currentUser ?? (await auth.signInAnonymously()).user;
      viewerId = user?.uid;
    }
    if (viewerId == null || viewerId.isEmpty) return;

    FeedService.warmUpItems(
      viewerId: viewerId,
      status: 'post',
      limit: 16,
    );
  } catch (_) {
    // Feed warm-up is opportunistic; the feed screen still loads normally.
  }
}

class SouqaliApp extends StatefulWidget {
  const SouqaliApp({
    super.key,
    required this.firebaseFuture,
    required this.sessionFuture,
    required this.cameraPrewarmFuture,
  });

  final Future<void> firebaseFuture;
  final Future<SellerSession?> sessionFuture;
  final Future<void> cameraPrewarmFuture;

  @override
  State<SouqaliApp> createState() => _SouqaliAppState();
}

class _SouqaliAppState extends State<SouqaliApp> {
  static const _deepLinkMethodChannel = MethodChannel('com.bizsooq.app/deep_links');
  static const _deepLinkEventChannel = EventChannel('com.bizsooq.app/deep_link_events');

  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  // Hoisted so a root rebuild can't recreate the future and re-show the splash.
  late final Future<AppUpdateDecision> _updateFuture =
      widget.firebaseFuture.then((_) => AppUpdateService.check());
  late final Future<List<dynamic>> _readyFuture = Future.wait([
    widget.firebaseFuture,
    widget.sessionFuture,
    _updateFuture,
    widget.cameraPrewarmFuture,
  ]);
  Timer? _androidUpdatePollTimer;
  bool _didShowUpdateDialog = false;
  bool _didRemoveNativeSplash = false;
  bool _didStartFlexibleUpdate = false;
  bool _isShowingFlexibleInstallPrompt = false;
  bool _deferFlexibleInstallPromptUntilResume = false;
  StreamSubscription<dynamic>? _deepLinkSubscription;
  String? _pendingDeepLink;
  bool _isOpeningDeepLink = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(_appLifecycleObserver);
    _initDeepLinks();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_appLifecycleObserver);
    _androidUpdatePollTimer?.cancel();
    _deepLinkSubscription?.cancel();
    super.dispose();
  }

  late final WidgetsBindingObserver _appLifecycleObserver =
      _SouqaliAppLifecycleObserver(
        onResumed: _handleAppResumed,
      );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'BIZSOOQ',
      // Lock Text Scaling to 1.0 globally to prevent UI breakage on phones with "Large Text" settings
      builder: (context, child) {
        final data = MediaQuery.of(context);
        return MediaQuery(
          data: data.copyWith(textScaler: TextScaler.noScaling),
          child: child!,
        );
      },
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0E7C66)),
        scaffoldBackgroundColor: const Color(0xFFF4FBF7),
        canvasColor: const Color(0xFFF4FBF7),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: Colors.black,
            statusBarIconBrightness: Brightness.light,
            statusBarBrightness: Brightness.dark,
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: FutureBuilder(
        future: _readyFuture,
        builder: (context, AsyncSnapshot<List<dynamic>> snapshot) {
          // While waiting, show a clean background shell
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SizedBox.shrink();
          }

          final session = snapshot.data?[1] as SellerSession?;
          final updateDecision = snapshot.data?[2] as AppUpdateDecision?;
          final home = session != null
              ? const SellerHomePage()
              : const SellerHomePage(isSellerMode: false);
          _removeNativeSplashOnce();
          if (updateDecision != null) {
            _handleUpdateDecision(updateDecision);
          }
          _flushPendingDeepLink();
          return home;
        },
      ),
    );
  }

  Future<void> _initDeepLinks() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      _deepLinkSubscription = _deepLinkEventChannel
          .receiveBroadcastStream()
          .listen((event) => _handleDeepLink(event?.toString()));
      try {
        final initialLink =
            await _deepLinkMethodChannel.invokeMethod<String>('getInitialLink');
        _handleDeepLink(initialLink);
      } catch (_) {}
    }
  }

  void _handleDeepLink(String? link) {
    final itemId = _itemIdFromDeepLink(link);
    if (itemId == null || itemId.isEmpty) return;
    _pendingDeepLink = itemId;
    _flushPendingDeepLink();
  }

  String? _itemIdFromDeepLink(String? link) {
    if (link == null || link.trim().isEmpty) return null;
    final uri = Uri.tryParse(link.trim());
    if (uri == null) return null;
    if (uri.scheme == 'bizsooq' && uri.host == 'listing') {
      return uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    }
    if ((uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host == 'bizsooq.com' &&
        uri.pathSegments.length >= 2 &&
        uri.pathSegments.first == 'listing') {
      return uri.pathSegments[1];
    }
    return null;
  }

  Future<void> _flushPendingDeepLink() async {
    final itemId = _pendingDeepLink;
    if (itemId == null || _isOpeningDeepLink) return;
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;

    _pendingDeepLink = null;
    _isOpeningDeepLink = true;
    try {
      await widget.firebaseFuture;
      final doc =
          await FirebaseFirestore.instance.collection('items').doc(itemId).get();
      if (!doc.exists || doc.data() == null) {
        return;
      }
      if (!mounted) return;
      navigator.push(
        MaterialPageRoute(
          builder: (_) => ItemDetailPage(
            itemId: itemId,
            itemData: doc.data()!,
          ),
        ),
      );
    } finally {
      _isOpeningDeepLink = false;
    }
  }

  void _removeNativeSplashOnce() {
    if (_didRemoveNativeSplash) return;
    _didRemoveNativeSplash = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FlutterNativeSplash.remove();
    });
  }

  void _showUpdateDialogOnce(
    AppUpdateDecision decision,
  ) {
    if (_didShowUpdateDialog) return;
    final context = _navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    _didShowUpdateDialog = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ForcedUpdateDialog(decision: decision),
      );
    });
  }

  void _handleUpdateDecision(AppUpdateDecision decision) {
    if (decision.isRequired) {
      _showUpdateDialogOnce(decision);
      return;
    }

    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    if (decision.shouldStartFlexibleUpdate) {
      _startFlexibleUpdateOnce();
    }
    if (decision.shouldPromptFlexibleInstall &&
        !_deferFlexibleInstallPromptUntilResume) {
      _androidUpdatePollTimer?.cancel();
      _showFlexibleInstallPrompt();
    }
  }

  Future<void> _startFlexibleUpdateOnce() async {
    if (_didStartFlexibleUpdate) return;
    _didStartFlexibleUpdate = true;
    final started = await AppUpdateService.startFlexibleUpdate();
    if (!started) return;
    _startAndroidUpdatePolling();
  }

  void _startAndroidUpdatePolling() {
    _androidUpdatePollTimer?.cancel();
    _androidUpdatePollTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _refreshAndroidUpdateState(),
    );
  }

  Future<void> _handleAppResumed() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    _deferFlexibleInstallPromptUntilResume = false;
    await _refreshAndroidUpdateState();
  }

  Future<void> _refreshAndroidUpdateState() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    final decision = await AppUpdateService.check();
    if (!mounted) return;
    _handleUpdateDecision(decision);
  }

  Future<void> _showFlexibleInstallPrompt() async {
    if (_isShowingFlexibleInstallPrompt) return;
    final context = _navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    _isShowingFlexibleInstallPrompt = true;
    final installNow = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const _FlexibleUpdateReadyDialog(),
    );
    _isShowingFlexibleInstallPrompt = false;

    if (installNow == true) {
      await AppUpdateService.completeFlexibleUpdate();
      return;
    }

    _deferFlexibleInstallPromptUntilResume = true;
  }
}

class _SouqaliAppLifecycleObserver with WidgetsBindingObserver {
  _SouqaliAppLifecycleObserver({required this.onResumed});

  final Future<void> Function() onResumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(onResumed());
    }
  }
}

class _ForcedUpdateDialog extends StatelessWidget {
  const _ForcedUpdateDialog({required this.decision});

  final AppUpdateDecision decision;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: const Text(
          'Update Required',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          decision.message,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, height: 1.35),
        ),
        actionsPadding: EdgeInsets.zero,
        actions: [
          SizedBox(
            width: double.infinity,
            height: 54,
            child: TextButton(
              onPressed: () => _openStore(decision.storeUrl),
              child: const Text(
                'Update',
                style: TextStyle(
                  color: Color(0xFFFF7801),
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openStore(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _FlexibleUpdateReadyDialog extends StatelessWidget {
  const _FlexibleUpdateReadyDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      title: const Text(
        'Update Ready',
        textAlign: TextAlign.center,
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      content: const Text(
        'A new update has been downloaded. Restart now to install it.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 16, height: 1.35),
      ),
      actionsPadding: EdgeInsets.zero,
      actions: [
        SizedBox(
          height: 54,
          child: Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text(
                    'Later',
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text(
                    'Install',
                    style: TextStyle(
                      color: Color(0xFFFF7801),
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
