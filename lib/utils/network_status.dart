import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';

class NetworkStatus {
  NetworkStatus._();

  static const noInternetMessage = 'No internet connection';

  static Future<bool> hasConnection() async {
    try {
      final result = await InternetAddress.lookup(
        'firebase.google.com',
      ).timeout(const Duration(seconds: 2));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } on SocketException {
      return false;
    } on TimeoutException {
      return false;
    } catch (_) {
      return true;
    }
  }

  static bool isOfflineError(Object error) {
    if (error is SocketException || error is TimeoutException) {
      return true;
    }
    if (error is FirebaseException) {
      final code = error.code.toLowerCase();
      return code == 'unavailable' ||
          code == 'deadline-exceeded' ||
          code == 'network-request-failed';
    }
    final text = error.toString().toLowerCase();
    return text.contains('socketexception') ||
        text.contains('failed host lookup') ||
        text.contains('network is unreachable') ||
        text.contains('network-request-failed') ||
        text.contains('unavailable');
  }
}
