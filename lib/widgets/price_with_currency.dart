import 'package:flutter/material.dart';

class PriceWithCurrency extends StatelessWidget {
  const PriceWithCurrency({
    super.key,
    required this.price,
    required this.style,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
  });

  final String price;
  final TextStyle style;
  final int maxLines;
  final TextOverflow overflow;

  @override
  Widget build(BuildContext context) {
    final trimmed = price.trim();
    if (trimmed.isEmpty || trimmed == 'Contact for Price') {
      return Text(
        trimmed,
        maxLines: maxLines,
        overflow: overflow,
        style: style,
      );
    }

    final withoutOmr = trimmed.replaceFirst(
      RegExp(r'^OMR\s+', caseSensitive: false),
      '',
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/images/omr_logo.png',
          width: (style.fontSize ?? 16) * 1.25,
          height: (style.fontSize ?? 16) * 0.9,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => Text('OMR', style: style),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            withoutOmr,
            maxLines: maxLines,
            overflow: overflow,
            style: style,
          ),
        ),
      ],
    );
  }
}
