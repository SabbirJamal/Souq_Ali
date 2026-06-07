import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'seller_session.dart';

class SellerSessionGuard {
  SellerSessionGuard._();

  static const invalidMessage =
      'Another device has logged into this account, Please login again to continue';

  static Future<bool> ensureActive(
    BuildContext context, {
    required VoidCallback onInvalid,
  }) async {
    final session = await SellerSession.current();
    if (session == null) {
      onInvalid();
      return false;
    }

    try {
      final ref = FirebaseFirestore.instance.collection('sellers').doc(session.sellerId);
      final doc = await ref.get();
      final data = doc.data();
      final activeSessionId = data?['active_session_id']?.toString() ?? '';

      if (activeSessionId.isEmpty) {
        await writeActiveSession(session);
        return true;
      }
      if (activeSessionId == session.sessionId) return true;
    } catch (_) {
      return true;
    }

    if (context.mounted) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 36),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 22),
                child: Text(
                  invalidMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                ),
              ),
              const Divider(height: 1),
              SizedBox(
                height: 64,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.black,
                    shape: const RoundedRectangleBorder(),
                  ),
                  child: const Text(
                    'OK',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    await SellerSession.clear();
    onInvalid();
    return false;
  }

  static Future<void> writeActiveSession(SellerSession session) {
    return FirebaseFirestore.instance.collection('sellers').doc(session.sellerId).set({
      'active_session_id': session.sessionId,
      'active_device_id': session.deviceId,
      'active_login_at': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
