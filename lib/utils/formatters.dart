String formatPrice(Object? value) {
  final text = value?.toString() ?? '';
  if (isZeroPrice(text)) {
    return '';
  }
  return text
      .replaceAll(RegExp(r'\s+per\s+', caseSensitive: false), ' / ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

bool isZeroPrice(String value) {
  final match = RegExp(r'\d+(?:\.\d+)?').firstMatch(value);
  if (match == null) {
    return false;
  }
  return (double.tryParse(match.group(0) ?? '') ?? -1) == 0;
}

String formatSellerPhone(Object? value) {
  final digits = value?.toString().replaceAll(RegExp(r'[^0-9]'), '') ?? '';
  if (digits.isEmpty) {
    return '';
  }
  if (digits.startsWith('968') && digits.length > 3) {
    return '+968 ${digits.substring(3)}';
  }
  return '+968 $digits';
}
