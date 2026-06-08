import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

Future<void> main() async {
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: 'AIzaSyBbfoGx0dS6Xymfgu4koLAVdHrPN-AKG_8',
      appId: '1:330917548315:android:b7664c8caf7bf46b84c3be',
      messagingSenderId: '330917548315',
      projectId: 'souqali-42fd9',
      storageBucket: 'souqali-42fd9.firebasestorage.app',
    ),
  );

  final snapshot =
      await FirebaseFirestore.instance.collection('items').count().get();

  // ignore: avoid_print
  print('Total items: ${snapshot.count}');
}
