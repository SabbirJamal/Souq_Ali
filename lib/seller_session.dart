import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

class SellerSession {
  static const _sellerIdKey = 'seller_id';
  static const _sellerNameKey = 'seller_name';
  static const _sellerPhoneKey = 'seller_phone';
  static const _sessionIdKey = 'seller_session_id';
  static const _deviceIdKey = 'device_install_id';

  const SellerSession({
    required this.sellerId,
    required this.name,
    required this.phoneNumber,
    required this.sessionId,
    required this.deviceId,
  });

  final String sellerId;
  final String name;
  final String phoneNumber;
  final String sessionId;
  final String deviceId;

  static SellerSession? _cached;

  static Future<SellerSession?> current() async {
    if (_cached != null) {
      return _cached;
    }

    final prefs = await SharedPreferences.getInstance();
    final sellerId = prefs.getString(_sellerIdKey);
    final phoneNumber = prefs.getString(_sellerPhoneKey);

    if (sellerId == null || phoneNumber == null) {
      return null;
    }

    _cached = SellerSession(
      sellerId: sellerId,
      name: prefs.getString(_sellerNameKey) ?? 'Seller',
      phoneNumber: phoneNumber,
      sessionId: prefs.getString(_sessionIdKey) ?? await _newSessionId(prefs),
      deviceId: await _deviceId(prefs),
    );
    return _cached;
  }

  static Future<SellerSession> save({
    required String sellerId,
    required String name,
    required String phoneNumber,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final sessionId = _makeId('session');
    final deviceId = await _deviceId(prefs);
    await prefs.setString(_sellerIdKey, sellerId);
    await prefs.setString(_sellerNameKey, name);
    await prefs.setString(_sellerPhoneKey, phoneNumber);
    await prefs.setString(_sessionIdKey, sessionId);
    _cached = SellerSession(
      sellerId: sellerId,
      name: name,
      phoneNumber: phoneNumber,
      sessionId: sessionId,
      deviceId: deviceId,
    );
    return _cached!;
  }

  static Future<void> updateName(String name) async {
    final session = await current();
    if (session == null) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sellerNameKey, name);
    _cached = SellerSession(
      sellerId: session.sellerId,
      name: name,
      phoneNumber: session.phoneNumber,
      sessionId: session.sessionId,
      deviceId: session.deviceId,
    );
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sellerIdKey);
    await prefs.remove(_sellerNameKey);
    await prefs.remove(_sellerPhoneKey);
    await prefs.remove(_sessionIdKey);
    _cached = null;
  }

  static Future<String> _newSessionId(SharedPreferences prefs) async {
    final id = _makeId('session');
    await prefs.setString(_sessionIdKey, id);
    return id;
  }

  static Future<String> _deviceId(SharedPreferences prefs) async {
    final existing = prefs.getString(_deviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = _makeId('device');
    await prefs.setString(_deviceIdKey, id);
    return id;
  }

  static String _makeId(String prefix) {
    final random = Random.secure();
    final suffix = List.generate(4, (_) => random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0')).join();
    return '$prefix-${DateTime.now().microsecondsSinceEpoch}-$suffix';
  }
}
