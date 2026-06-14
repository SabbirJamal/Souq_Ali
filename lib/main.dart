import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart' as permissions;
import 'package:url_launcher/url_launcher.dart';

import 'camera_capture_page.dart';
import 'seller_home_page.dart';
import 'seller_session.dart';
import 'services/app_update_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: SystemUiOverlay.values,
  );
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.black,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
  ));

  // Parallelize Firebase and Session loading
  final firebaseFuture = Firebase.initializeApp();
  final sessionFuture = SellerSession.current();
  unawaited(_prewarmCameraIfPermitted());

  runApp(SouqaliApp(
    firebaseFuture: firebaseFuture,
    sessionFuture: sessionFuture,
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

class SouqaliApp extends StatefulWidget {
  const SouqaliApp({
    super.key,
    required this.firebaseFuture,
    required this.sessionFuture,
  });

  final Future<void> firebaseFuture;
  final Future<SellerSession?> sessionFuture;

  @override
  State<SouqaliApp> createState() => _SouqaliAppState();
}

class _SouqaliAppState extends State<SouqaliApp> {
  // Hoisted so a root rebuild can't recreate the future and re-show the splash.
  late final Future<AppUpdateDecision> _updateFuture =
      widget.firebaseFuture.then((_) => AppUpdateService.check());
  late final Future<List<dynamic>> _readyFuture =
      Future.wait([widget.firebaseFuture, widget.sessionFuture, _updateFuture]);
  bool _didShowUpdateDialog = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
            return const Scaffold(
              backgroundColor: Color(0xFFF4FBF7),
              body: Center(
                child: SizedBox(
                  width: 100,
                  height: 100,
                  child: Image(
                    image: AssetImage('assets/branding/logo.png'),
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            );
          }

          final session = snapshot.data?[1] as SellerSession?;
          final updateDecision = snapshot.data?[2] as AppUpdateDecision?;
          final home = session != null
              ? const SellerHomePage()
              : const SellerHomePage(isSellerMode: false);
          if (updateDecision?.isRequired == true) {
            _showUpdateDialogOnce(context, updateDecision!);
          }
          return home;
        },
      ),
    );
  }

  void _showUpdateDialogOnce(
    BuildContext context,
    AppUpdateDecision decision,
  ) {
    if (_didShowUpdateDialog) return;
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
