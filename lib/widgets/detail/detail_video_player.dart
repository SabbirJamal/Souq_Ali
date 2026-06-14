import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../media_carousel.dart';

class DetailVideoPlayer extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final videoController = controller;
    return Stack(
      fit: StackFit.expand,
      alignment: Alignment.center,
      children: [
        Transform.scale(
          scale: videoScale,
          child: VideoPreview(
            url: url,
            thumbnailUrl: null,
            fit: BoxFit.contain,
            controller: videoController,
            initializeFuture: initializeFuture,
            autoPlay: autoPlay,
            pauseSignal: pauseSignal,
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
        if (showPauseIcon)
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
