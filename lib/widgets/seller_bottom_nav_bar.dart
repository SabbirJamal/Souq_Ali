import 'package:flutter/material.dart';

class SellerBottomNavBar extends StatelessWidget {
  const SellerBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.backgroundColor = const Color(0xFFF4FBF7),
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: backgroundColor,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewPaddingOf(context).bottom,
        ),
        child: SizedBox(
          height: 48,
          child: Row(
            children: [
              _SellerBottomNavItem(
                index: 0,
                currentIndex: currentIndex,
                icon: Icons.home,
                size: 33,
                label: 'Home',
                onTap: onTap,
              ),
              _SellerBottomNavItem(
                index: 1,
                currentIndex: currentIndex,
                label: 'Live',
                onTap: onTap,
              ),
              _SellerBottomNavItem(
                index: 2,
                currentIndex: currentIndex,
                icon: Icons.add_circle_outline,
                size: 29,
                label: 'Add',
                onTap: onTap,
              ),
              _SellerBottomNavItem(
                index: 3,
                currentIndex: currentIndex,
                icon: Icons.person,
                size: 29,
                label: 'Listings',
                onTap: onTap,
              ),
              _SellerBottomNavItem(
                index: 4,
                currentIndex: currentIndex,
                icon: Icons.settings,
                size: 29,
                label: 'Settings',
                onTap: onTap,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SellerBottomNavItem extends StatelessWidget {
  const _SellerBottomNavItem({
    required this.index,
    required this.currentIndex,
    required this.label,
    required this.onTap,
    this.icon,
    this.size = 29,
  });

  final int index;
  final int currentIndex;
  final IconData? icon;
  final double size;
  final String label;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final isSelected = currentIndex == index;
    const touchShape = StadiumBorder();

    return Expanded(
      child: Center(
        child: Material(
          color: Colors.transparent,
          shape: touchShape,
          clipBehavior: Clip.antiAlias,
          child: InkResponse(
            onTap: () => onTap(index),
            containedInkWell: true,
            customBorder: touchShape,
            radius: 58,
            splashColor: Colors.black12,
            highlightColor: Colors.black12,
            child: SizedBox(
              width: 118,
              height: 64,
              child: Center(
                child: icon == null
                    ? const Text(
                        'LIVE',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFFFF0000),
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                      )
                    : Icon(
                        icon,
                        size: size,
                        color: isSelected
                            ? const Color(0xFFFF7801)
                            : Colors.grey,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
