import 'package:flutter/services.dart';

const double maxAllowedPrice = 1000000.0;

String? normalizePriceInput(String value) {
  final cleanValue = value.replaceAll(',', '').trim();
  if (!RegExp(r'^\d+(\.\d{0,3})?$').hasMatch(cleanValue)) return null;
  final parsed = double.tryParse(cleanValue);
  if (parsed == null || parsed <= 0 || parsed > maxAllowedPrice) return null;
  return parsed.toStringAsFixed(3);
}

class PriceInputFormatter extends TextInputFormatter {
  const PriceInputFormatter();

  static final _validPrice = RegExp(r'^\d*\.?\d{0,3}$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.replaceAll(',', '');
    if (text.isEmpty || text == '.') return newValue;
    if (!_validPrice.hasMatch(text)) return oldValue;
    final parsed = double.tryParse(text);
    if (parsed != null && parsed > maxAllowedPrice) return oldValue;
    return newValue;
  }
}
