import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'seller_home_page.dart';
import 'seller_login_page.dart';
import 'seller_session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const SouqaliApp());
}

class SouqaliApp extends StatelessWidget {
  const SouqaliApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Souqali',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0E7C66)),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: FutureBuilder<SellerSession?>(
        future: SellerSession.current(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          if (snapshot.data != null) {
            return const SellerHomePage();
          }

          return const SellerLoginPage();
        },
      ),
    );
  }
}
