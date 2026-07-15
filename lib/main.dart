import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
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
import 'utils/share_links.dart';
import 'utils/system_ui_styles.dart';
import 'widgets/media_carousel.dart';

final Set<String> _startupPrefetchedThumbnailUrls = {};

Future<void> main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  AppSystemUi.applyNormal();

  // Parallelize Firebase and Session loading
  final firebaseFuture = Firebase.initializeApp();
  final sessionFuture = SellerSession.current();
  final cameraPrewarmFuture = _prewarmCameraIfPermitted();
  unawaited(_warmInitialFeeds(firebaseFuture, sessionFuture));

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

Future<void> _warmInitialFeeds(
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

    FeedService.warmUpItems(viewerId: viewerId, status: 'post', limit: 12);
    FeedService.warmUpItems(
      viewerId: viewerId,
      status: 'live',
      limit: 12,
      onResult: (result) => _prefetchStartupThumbnails(result.items),
    );
  } catch (_) {
    // Feed warm-up is opportunistic; feed/live screens still load normally.
  }
}

void _prefetchStartupThumbnails(List<FeedItem> items) {
  const limit = 4;
  var queued = 0;

  for (final item in items) {
    if (queued >= limit) break;
    final media = mediaItemsFromMap(item.data);
    if (media.isEmpty) continue;

    final url = media.first.thumbnailUrl?.trim() ?? '';
    if (url.isEmpty || !_startupPrefetchedThumbnailUrls.add(url)) continue;

    queued += 1;
    final stream = CachedNetworkImageProvider(
      url,
      maxWidth: 500,
    ).resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (_, _) => stream.removeListener(listener),
      onError: (_, _) => stream.removeListener(listener),
    );
    stream.addListener(listener);
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
  bool _didShowUpdateDialog = false;
  bool _didRemoveNativeSplash = false;
  bool _didStartImmediateUpdate = false;
  StreamSubscription<dynamic>? _deepLinkSubscription;
  String? _pendingDeepLink;
  bool _isOpeningDeepLink = false;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }

  @override
  void dispose() {
    _deepLinkSubscription?.cancel();
    super.dispose();
  }

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
        appBarTheme: AppBarTheme(
          systemOverlayStyle: AppSystemUi.normalStyle,
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
    final itemId = _linkTokenFromDeepLink(link);
    if (itemId == null || itemId.isEmpty) return;
    _pendingDeepLink = itemId;
    _flushPendingDeepLink();
  }

  String? _linkTokenFromDeepLink(String? link) {
    if (link == null || link.trim().isEmpty) return null;
    final uri = Uri.tryParse(link.trim());
    if (uri == null) return null;
    if (uri.scheme == 'bizsooq' && (uri.host == 'listing' || uri.host == 'i')) {
      return uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    }
    if ((uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host == 'bizsooq.com' &&
        uri.pathSegments.length >= 2 &&
        (uri.pathSegments.first == 'listing' || uri.pathSegments.first == 'i')) {
      return uri.pathSegments[1];
    }
    return null;
  }

  Future<void> _flushPendingDeepLink() async {
    final linkToken = _pendingDeepLink;
    if (linkToken == null || _isOpeningDeepLink) return;
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;

    _pendingDeepLink = null;
    _isOpeningDeepLink = true;
    try {
      await widget.firebaseFuture;
      final doc = await _itemDocFromLinkToken(linkToken);
      if (!doc.exists || doc.data() == null) {
        return;
      }
      if (!mounted) return;
      navigator.push(
        MaterialPageRoute(
          builder: (_) => ItemDetailPage(
            itemId: doc.id,
            itemData: doc.data()!,
          ),
        ),
      );
    } finally {
      _isOpeningDeepLink = false;
    }
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _itemDocFromLinkToken(
    String token,
  ) async {
    final items = FirebaseFirestore.instance.collection('items');
    final directDoc = await items.doc(token).get();
    if (directDoc.exists) return directDoc;

    final codeSnapshot = await items
        .where(shareCodeField, isEqualTo: token.toUpperCase())
        .limit(1)
        .get();
    if (codeSnapshot.docs.isNotEmpty) return codeSnapshot.docs.first;
    return directDoc;
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

    if (decision.shouldStartImmediateUpdate) {
      _startImmediateUpdateOnce(decision);
    }
  }

  Future<void> _startImmediateUpdateOnce(AppUpdateDecision decision) async {
    if (_didStartImmediateUpdate) return;
    _didStartImmediateUpdate = true;
    final updated = await AppUpdateService.startImmediateUpdate();
    if (!updated && mounted) {
      _showUpdateDialogOnce(decision);
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
