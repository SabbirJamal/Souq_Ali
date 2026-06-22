String normalizeItemSearchText(Object? value) {
  return value
      ?.toString()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\u0600-\u06ff]+'), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ') ??
      '';
}

Map<String, Object> buildItemSearchData({
  required Object? itemName,
  required Object? location,
  required Object? price,
  required Object? sellerName,
  required Object? status,
  required Object? priceUnit,
}) {
  final text = [
    itemName,
    location,
    price,
    sellerName,
    status,
    priceUnit,
  ].map(normalizeItemSearchText).where((part) => part.isNotEmpty).join(' ');

  final keywords = <String>{};
  for (final word in text.split(' ')) {
    if (word.isEmpty) continue;
    final max = word.length < 20 ? word.length : 20;
    for (var i = 1; i <= max; i++) {
      keywords.add(word.substring(0, i));
    }
  }

  return {
    'search_text': text,
    'search_keywords': keywords.take(500).toList(growable: false),
  };
}
