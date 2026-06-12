import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class AppVideoSeekBar extends StatefulWidget {
  const AppVideoSeekBar({super.key, required this.controller});

  final VideoPlayerController controller;

  @override
  State<AppVideoSeekBar> createState() => _AppVideoSeekBarState();
}

class _AppVideoSeekBarState extends State<AppVideoSeekBar> {
  double? _dragValue;
  Timer? _seekThrottle;

  @override
  void dispose() {
    _seekThrottle?.cancel();
    super.dispose();
  }

  void _seekTo(double milliseconds, {bool immediate = false}) {
    _dragValue = milliseconds;
    if (immediate) {
      _seekThrottle?.cancel();
      _seekThrottle = null;
      unawaited(widget.controller.seekTo(Duration(milliseconds: milliseconds.round())));
      return;
    }
    if (_seekThrottle?.isActive == true) return;
    _seekThrottle = Timer(const Duration(milliseconds: 80), () {
      final value = _dragValue;
      if (value == null) return;
      unawaited(widget.controller.seekTo(Duration(milliseconds: value.round())));
    });
  }

  String _formatTime(Duration duration) {
    final total = duration.inSeconds;
    final minutes = total ~/ 60;
    final seconds = total % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: widget.controller,
            builder: (context, value, _) {
              final duration = value.duration;
              final max = duration.inMilliseconds <= 0
                  ? 1.0
                  : duration.inMilliseconds.toDouble();
              final current =
                  (_dragValue ?? value.position.inMilliseconds.toDouble())
                      .clamp(0.0, max)
                      .toDouble();
              return Row(
                children: [
                  SizedBox(
                    width: 38,
                    child: Text(
                      _formatTime(Duration(milliseconds: current.round())),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        activeTrackColor: const Color(0xFFFF7801),
                        inactiveTrackColor: Colors.white30,
                        thumbColor: Colors.white,
                        overlayColor: Colors.white24,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 12,
                        ),
                      ),
                      child: Slider(
                        min: 0,
                        max: max,
                        value: current,
                        onChanged: (next) {
                          setState(() => _dragValue = next);
                          _seekTo(next);
                        },
                        onChangeEnd: (next) {
                          _seekTo(next, immediate: true);
                          setState(() => _dragValue = null);
                        },
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 38,
                    child: Text(
                      _formatTime(duration),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
