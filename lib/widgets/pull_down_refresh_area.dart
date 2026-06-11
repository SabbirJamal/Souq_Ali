import 'package:flutter/material.dart';

class PullDownRefreshArea extends StatefulWidget {
  const PullDownRefreshArea({
    super.key,
    required this.child,
    required this.onRefresh,
    this.color = const Color(0xFFFF7801),
    this.onPullExtentChanged,
  });

  final Widget child;
  final Future<void> Function() onRefresh;
  final Color color;
  final ValueChanged<double>? onPullExtentChanged;

  @override
  State<PullDownRefreshArea> createState() => _PullDownRefreshAreaState();
}

class _PullDownRefreshAreaState extends State<PullDownRefreshArea> {
  static const _triggerExtent = 54.0;
  static const _maxExtent = 76.0;

  double _pullExtent = 0;
  bool _isRefreshing = false;

  void _setPullExtent(double value) {
    if (_pullExtent == value) return;
    setState(() => _pullExtent = value);
    widget.onPullExtentChanged?.call(value);
  }

  bool _handleScroll(ScrollNotification notification) {
    if (_isRefreshing) return false;

    final atTop = notification.metrics.pixels <=
        notification.metrics.minScrollExtent + 0.5;

    if (notification is OverscrollNotification &&
        atTop &&
        notification.overscroll < 0) {
      _setPullExtent(
        (_pullExtent + (-notification.overscroll * 0.55)).clamp(0, _maxExtent),
      );
      return false;
    }

    if (notification is OverscrollNotification &&
        _pullExtent > 0 &&
        notification.overscroll > 0) {
      _setPullExtent(
        (_pullExtent - (notification.overscroll * 0.9)).clamp(0, _maxExtent),
      );
      return false;
    }

    if (notification is ScrollUpdateNotification &&
        _pullExtent > 0 &&
        (notification.scrollDelta ?? 0) > 0) {
      _setPullExtent(
        (_pullExtent - ((notification.scrollDelta ?? 0) * 1.2)).clamp(0, _maxExtent),
      );
      return false;
    }

    if (notification is ScrollEndNotification && _pullExtent > 0) {
      if (_pullExtent >= _triggerExtent) {
        _refresh();
      } else {
        _setPullExtent(0);
      }
    }

    return false;
  }

  Future<void> _refresh() async {
    setState(() {
      _isRefreshing = true;
      _pullExtent = 0;
    });
    widget.onPullExtentChanged?.call(0);
    await widget.onRefresh();
    if (mounted) {
      setState(() {
        _isRefreshing = false;
        _pullExtent = 0;
      });
      widget.onPullExtentChanged?.call(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        AnimatedContainer(
          transform: Matrix4.translationValues(0, _pullExtent, 0),
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: NotificationListener<ScrollNotification>(
            onNotification: _handleScroll,
            child: widget.child,
          ),
        ),
      ],
    );
  }
}
