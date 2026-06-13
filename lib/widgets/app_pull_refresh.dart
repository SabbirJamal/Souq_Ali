import 'package:flutter/material.dart';

class AppPullRefresh extends StatefulWidget {
  const AppPullRefresh({
    super.key,
    required this.child,
    required this.onRefresh,
    this.triggerDistance = 36,
    this.indicatorTop = 100,
    this.color = const Color(0xFFFF7801),
  });

  final Widget child;
  final Future<void> Function() onRefresh;
  final double triggerDistance;
  final double indicatorTop;
  final Color color;

  @override
  State<AppPullRefresh> createState() => _AppPullRefreshState();
}

class _AppPullRefreshState extends State<AppPullRefresh>
    with SingleTickerProviderStateMixin {
  bool _refreshing = false;
  bool _dragStartedAtTop = false;
  double _pullDistance = 0;
  late final AnimationController _spinController;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
  }

  @override
  void dispose() {
    _spinController.dispose();
    super.dispose();
  }

  void _setPullDistance(double value) {
    if (_pullDistance == value) return;
    setState(() => _pullDistance = value);
  }

  bool _handleScroll(ScrollNotification notification) {
    if (_refreshing) return false;
    final atTop =
        notification.metrics.pixels <= notification.metrics.minScrollExtent + 0.5;

    if (notification is ScrollStartNotification) {
      _dragStartedAtTop = atTop && notification.dragDetails != null;
      _setPullDistance(0);
      return false;
    }

    if (!_dragStartedAtTop) {
      if (notification is ScrollEndNotification) {
        _setPullDistance(0);
      }
      return false;
    }

    if (notification is OverscrollNotification &&
        atTop &&
        notification.overscroll < 0) {
      _setPullDistance(_pullDistance + -notification.overscroll);
      return false;
    }

    if (notification is ScrollUpdateNotification &&
        _pullDistance > 0 &&
        (notification.scrollDelta ?? 0) > 0) {
      _setPullDistance(
        (_pullDistance - (notification.scrollDelta ?? 0)).clamp(0, 1000),
      );
      return false;
    }

    if (notification is ScrollEndNotification) {
      final shouldRefresh =
          _dragStartedAtTop && _pullDistance >= widget.triggerDistance;
      if (!shouldRefresh) _setPullDistance(0);
      _dragStartedAtTop = false;
      if (shouldRefresh) {
        _refresh();
      }
    }

    return false;
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() {
      _refreshing = true;
      _pullDistance = widget.triggerDistance;
    });
    _spinController.repeat();
    try {
      await widget.onRefresh();
    } finally {
      _spinController.stop();
      if (mounted) {
        setState(() {
          _refreshing = false;
          _pullDistance = 0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _handleScroll,
          child: widget.child,
        ),
        _RefreshBubble(
          progress: (_pullDistance / widget.triggerDistance).clamp(0.0, 1.0),
          top: widget.indicatorTop,
          color: widget.color,
          refreshing: _refreshing,
          spinController: _spinController,
        ),
      ],
    );
  }
}

class _RefreshBubble extends StatelessWidget {
  const _RefreshBubble({
    required this.progress,
    required this.top,
    required this.color,
    required this.refreshing,
    required this.spinController,
  });

  final double progress;
  final double top;
  final Color color;
  final bool refreshing;
  final AnimationController spinController;

  @override
  Widget build(BuildContext context) {
    if (progress <= 0 && !refreshing) return const SizedBox.shrink();
    final eased = Curves.easeOutCubic.transform(progress);
    final currentTop = top * eased;
    final scale = 0.78 + (0.22 * eased);

    return Positioned(
      top: currentTop,
      left: 0,
      right: 0,
      child: Center(
        child: RepaintBoundary(
          child: Opacity(
            opacity: eased,
            child: Transform.scale(
              scale: scale,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.22),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: SizedBox(
                  width: 42,
                  height: 42,
                  child: Center(
                    child: refreshing
                        ? RotationTransition(
                            turns: spinController,
                            child: Icon(
                              Icons.refresh_rounded,
                              color: color,
                              size: 29,
                            ),
                          )
                        : Transform.rotate(
                            angle: progress * 5.8,
                            child: Icon(
                              Icons.refresh_rounded,
                              color: color,
                              size: 29,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
