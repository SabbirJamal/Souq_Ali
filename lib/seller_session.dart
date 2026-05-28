import 'package:shared_preferences/shared_preferences.dart';

class SellerSession {
  static const _sellerIdKey = 'seller_id';
  static const _sellerNameKey = 'seller_name';
  static const _sellerPhoneKey = 'seller_phone';

  const SellerSession({
    required this.sellerId,
    required this.name,
    required this.phoneNumber,
  });

  final String sellerId;
  final String name;
  final String phoneNumber;

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
    );
    return _cached;
  }

  static Future<void> save({
    required String sellerId,
    required String name,
    required String phoneNumber,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sellerIdKey, sellerId);
    await prefs.setString(_sellerNameKey, name);
    await prefs.setString(_sellerPhoneKey, phoneNumber);
    _cached = SellerSession(
      sellerId: sellerId,
      name: name,
      phoneNumber: phoneNumber,
    );
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sellerIdKey);
    await prefs.remove(_sellerNameKey);
    await prefs.remove(_sellerPhoneKey);
    _cached = null;
  }
}
