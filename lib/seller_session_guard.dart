import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'seller_session.dart';

class SellerSessionGuard {
  SellerSessionGuard._();

  static const invalidMessage =
      'Another device has logged into this account, Please login again to continue';
  static const blockedMessage = 'Account Blocked, Contact\n$_supportPhone';
  static const _supportPhone = '+968 77283599';
  static const _validCacheDuration = Duration(seconds: 45);
  static String? _cachedValidSessionKey;
  static DateTime? _cachedValidUntil;

  static Future<bool> ensureActive(
    BuildContext context, {
    required VoidCallback onInvalid,
  }) async {
    final session = await SellerSession.current();
    if (session == null) {
      onInvalid();
      return false;
    }

    final sessionKey = _sessionKey(session);
    final now = DateTime.now();
    final cachedUntil = _cachedValidUntil;
    if (_cachedValidSessionKey == sessionKey &&
        cachedUntil != null &&
        now.isBefore(cachedUntil)) {
      return true;
    }

    try {
      final ref = FirebaseFirestore.instance.collection('sellers').doc(session.sellerId);
      final doc = await ref.get();
      if (!doc.exists) {
        await _invalidate(onInvalid);
        return false;
      }
      final data = doc.data();
      final status = data?['status']?.toString().trim().toLowerCase() ?? '';
      if (status == 'suspended' || status == 'blocked') {
        _clearValidSessionCache();
        if (context.mounted) {
          await showBlockedAccountDialog(context);
        }
        await _invalidate(onInvalid);
        return false;
      }
      final activeSessionId = data?['active_session_id']?.toString() ?? '';

      if (activeSessionId.isEmpty) {
        await writeActiveSession(session);
        _cacheValidSession(session);
        return true;
      }
      if (activeSessionId == session.sessionId) {
        _cacheValidSession(session);
        return true;
      }
    } catch (_) {
      return true;
    }

    _clearValidSessionCache();
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
                width: double.infinity,
                height: 64,
                child: InkWell(
                  onTap: () => Navigator.pop(context),
                  child: const Center(
                    child: Text(
                    'OK',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    await _invalidate(onInvalid);
    return false;
  }

  static Future<void> writeActiveSession(SellerSession session) {
    _cacheValidSession(session);
    return FirebaseFirestore.instance.collection('sellers').doc(session.sellerId).set({
      'active_session_id': session.sessionId,
      'active_device_id': session.deviceId,
      'active_login_at': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static String _sessionKey(SellerSession session) =>
      '${session.sellerId}|${session.sessionId}|${session.deviceId}';

  static void _cacheValidSession(SellerSession session) {
    _cachedValidSessionKey = _sessionKey(session);
    _cachedValidUntil = DateTime.now().add(_validCacheDuration);
  }

  static void _clearValidSessionCache() {
    _cachedValidSessionKey = null;
    _cachedValidUntil = null;
  }

  static Future<void> _invalidate(VoidCallback onInvalid) async {
    _clearValidSessionCache();
    await SellerSession.clear();
    onInvalid();
  }

  static Future<void> showBlockedAccountDialog(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 36),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                onPressed: () => Navigator.pop(dialogContext),
                icon: const Icon(Icons.close),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(22, 0, 22, 22),
              child: Text(
                blockedMessage,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
            ),
            const Divider(height: 1),
            SizedBox(
              height: 64,
              child: Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => _callSupport(dialogContext),
                      icon: const Icon(Icons.call),
                      label: const Text('Call'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.blue,
                        shape: const RoundedRectangleBorder(),
                        textStyle: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => _whatsappSupport(dialogContext),
                      icon: const FaIcon(FontAwesomeIcons.whatsapp),
                      label: const Text('Whatsapp'),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF16A34A),
                        shape: const RoundedRectangleBorder(),
                        textStyle: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
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
  }

  static Future<void> _callSupport(BuildContext dialogContext) async {
    Navigator.pop(dialogContext);
    await launchUrl(Uri(scheme: 'tel', path: _supportPhone));
  }

  static Future<void> _whatsappSupport(BuildContext dialogContext) async {
    Navigator.pop(dialogContext);
    final digits = _supportPhone.replaceAll(RegExp(r'[^0-9]'), '');
    await launchUrl(
      Uri.parse('https://wa.me/$digits'),
      mode: LaunchMode.externalApplication,
    );
  }
}
