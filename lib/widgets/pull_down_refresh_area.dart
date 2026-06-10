import 'package:flutter/material.dart';

class PullDownRefreshArea extends StatefulWidget {
  const PullDownRefreshArea({
    super.key,
    required this.child,
    required this.onRefresh,
    this.color = const Color(0xFFFF7801),
  });

  final Widget child;
  final Future<void> Function() onRefresh;
  final Color color;

  @override
  State<PullDownRefreshArea> createState() => _PullDownRefreshAreaState();
}

class _PullDownRefreshAreaState extends State<PullDownRefreshArea> {
  static const _triggerExtent = 54.0;
  static const _maxExtent = 76.0;

  double _pullExtent = 0;
  bool _isRefreshing = false;

  bool _handleScroll(ScrollNotification notification) {
    if (_isRefreshing) return false;

    final atTop = notification.metrics.pixels <=
        notification.metrics.minScrollExtent + 0.5;

    if (notification is OverscrollNotification &&
        atTop &&
        notification.overscroll < 0) {
      setState(() {
        _pullExtent =
            (_pullExtent + (-notification.overscroll * 0.55)).clamp(0, _maxExtent);
      });
      return false;
    }

    if (notification is OverscrollNotification &&
        _pullExtent > 0 &&
        notification.overscroll > 0) {
      setState(() {
        _pullExtent = (_pullExtent - (notification.overscroll * 0.9)).clamp(0, _maxExtent);
      });
      return false;
    }

    if (notification is ScrollUpdateNotification &&
        _pullExtent > 0 &&
        (notification.scrollDelta ?? 0) > 0) {
      setState(() {
        _pullExtent = (_pullExtent - ((notification.scrollDelta ?? 0) * 1.2)).clamp(0, _maxExtent);
      });
      return false;
    }

    if (notification is ScrollEndNotification && _pullExtent > 0) {
      if (_pullExtent >= _triggerExtent) {
        _refresh();
      } else {
        setState(() => _pullExtent = 0);
      }
    }

    return false;
  }

  Future<void> _refresh() async {
    setState(() {
      _isRefreshing = true;
      _pullExtent = 0;
    });
    await widget.onRefresh();
    if (mounted) {
      setState(() {
        _isRefreshing = false;
        _pullExtent = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_pullExtent / _triggerExtent).clamp(0.0, 1.0);

    return Stack(
      children: [
        Positioned(
          top: 10,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Opacity(
              opacity: progress,
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    value: _isRefreshing ? null : progress,
                    color: widget.color,
                  ),
                ),
              ),
            ),
          ),
        ),
        AnimatedSlide(
          offset: Offset(0, _pullExtent / 420),
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
