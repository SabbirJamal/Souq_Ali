import 'dart:math';

const String shareCodeField = 'share_code';
const int shareCodeLength = 5;

const String _shareAlphabet = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
final Random _shareCodeRandom = Random.secure();

String generateShareCode() {
  return List.generate(
    shareCodeLength,
    (_) => _shareAlphabet[_shareCodeRandom.nextInt(_shareAlphabet.length)],
  ).join();
}

String shareCodeFromItem(Map<String, dynamic> item, String itemId) {
  final code = item[shareCodeField]?.toString().trim();
  return code == null || code.isEmpty ? itemId : code;
}
