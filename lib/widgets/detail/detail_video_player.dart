import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../media_carousel.dart';

class DetailVideoPlayer extends StatefulWidget {
  const DetailVideoPlayer({
    super.key,
    required this.url,
    required this.videoScale,
    required this.autoPlay,
    required this.pauseSignal,
    required this.showPauseIcon,
    this.controller,
    this.initializeFuture,
  });

  final String url;
  final double videoScale;
  final bool autoPlay;
  final ValueNotifier<int> pauseSignal;
  final bool showPauseIcon;
  final VideoPlayerController? controller;
  final Future<void>? initializeFuture;

  @override
  State<DetailVideoPlayer> createState() => _DetailVideoPlayerState();
}

class _DetailVideoPlayerState extends State<DetailVideoPlayer>
    with WidgetsBindingObserver {
  VideoPlayerController? _observedController;
  bool _wakeLockEnabled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _attachController(widget.controller);
  }

  @override
  void didUpdateWidget(covariant DetailVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _detachController(oldWidget.controller);
      _attachController(widget.controller);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _setWakeLock(false);
    } else if (state == AppLifecycleState.resumed) {
      _syncWakeLock();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _detachController(_observedController);
    _setWakeLock(false);
    super.dispose();
  }

  void _attachController(VideoPlayerController? controller) {
    _observedController = controller;
    controller?.addListener(_syncWakeLock);
    _syncWakeLock();
  }

  void _detachController(VideoPlayerController? controller) {
    controller?.removeListener(_syncWakeLock);
    if (identical(_observedController, controller)) {
      _observedController = null;
    }
    _setWakeLock(false);
  }

  void _syncWakeLock() {
    final value = _observedController?.value;
    _setWakeLock(value != null && value.isInitialized && value.isPlaying);
  }

  void _setWakeLock(bool enabled) {
    if (_wakeLockEnabled == enabled) return;
    _wakeLockEnabled = enabled;
    if (enabled) {
      WakelockPlus.enable();
    } else {
      WakelockPlus.disable();
    }
  }

  @override
  Widget build(BuildContext context) {
    final videoController = widget.controller;
    return Stack(
      fit: StackFit.expand,
      alignment: Alignment.center,
      children: [
        Transform.scale(
          scale: widget.videoScale,
          child: VideoPreview(
            url: widget.url,
            thumbnailUrl: null,
            fit: BoxFit.contain,
            controller: videoController,
            initializeFuture: widget.initializeFuture,
            autoPlay: widget.autoPlay,
            pauseSignal: widget.pauseSignal,
            showPlayButton: false,
            playIconSize: 72,
          ),
        ),
        if (videoController != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _DetailVideoProgressStrip(controller: videoController),
          ),
        if (widget.showPauseIcon)
          Center(
            child: IgnorePointer(
              child: SizedBox.square(
                dimension: 45,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.62),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.pause,
                    color: Colors.white,
                    size: 29,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _DetailVideoProgressStrip extends StatelessWidget {
  const _DetailVideoProgressStrip({required this.controller});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          final durationMs = value.duration.inMilliseconds;
          if (!value.isInitialized || durationMs <= 0) {
            return const SizedBox.shrink();
          }

          final played = (value.position.inMilliseconds / durationMs)
              .clamp(0.0, 1.0)
              .toDouble();
          final buffered = value.buffered.fold<double>(
            0,
            (maxEnd, range) {
              final loaded = range.end.inMilliseconds / durationMs;
              return loaded > maxEnd ? loaded : maxEnd;
            },
          ).clamp(0.0, 1.0).toDouble();

          return SizedBox(
            height: 3,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: Colors.black),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: buffered,
                  child: const ColoredBox(color: Colors.white),
                ),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: played,
                  child: const ColoredBox(color: Color(0xFFFF7801)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
