import 'package:flutter/material.dart';

class RiyalCurrencyIcon extends StatelessWidget {
  const RiyalCurrencyIcon({super.key, this.size = 22, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final effectiveColor =
        color ?? IconTheme.of(context).color ?? Colors.black;

    return Image.asset(
      'assets/images/omr_logo.png',
      width: size * 1.35,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => Icon(
        Icons.payments_outlined,
        color: effectiveColor,
        size: size,
      ),
    );
  }
}

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
        RiyalCurrencyIcon(
          size: (style.fontSize ?? 16) * 1.25,
          color: style.color,
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
