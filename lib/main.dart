import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'seller_home_page.dart';
import 'seller_session.dart';

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

  runApp(SouqaliApp(
    firebaseFuture: firebaseFuture,
    sessionFuture: sessionFuture,
  ));
}

class SouqaliApp extends StatelessWidget {
  const SouqaliApp({
    super.key,
    required this.firebaseFuture,
    required this.sessionFuture,
  });

  final Future<void> firebaseFuture;
  final Future<SellerSession?> sessionFuture;

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
        future: Future.wait([firebaseFuture, sessionFuture]),
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
          return session != null
              ? const SellerHomePage()
              : const SellerHomePage(isSellerMode: false);
        },
      ),
    );
  }
}
