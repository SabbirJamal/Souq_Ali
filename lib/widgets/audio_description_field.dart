import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart' as device_permissions;
import 'package:record/record.dart';

class AudioDescriptionField extends StatefulWidget {
  const AudioDescriptionField({
    super.key,
    required this.isDisabled,
    required this.resetToken,
    required this.onChanged,
    this.initialUrl,
    this.initialDuration = Duration.zero,
    this.label = 'Voice Note',
  });

  final bool isDisabled;
  final int resetToken;
  final String? initialUrl;
  final Duration initialDuration;
  final void Function(String? path, Duration duration, bool removeExisting) onChanged;
  final String label;

  @override
  State<AudioDescriptionField> createState() => _AudioDescriptionFieldState();
}

class _AudioDescriptionFieldState extends State<AudioDescriptionField> {
  static const _maxDuration = Duration(seconds: 30);
  static const _cancelSlideDistance = -80.0;

  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  Timer? _recordTimer;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<void>? _completeSubscription;
  String? _audioPath;
  String? _existingUrl;
  List<double> _waveSamples = const [];
  late Duration _recordedDuration;
  Duration _recordElapsed = Duration.zero;
  Duration _playbackPosition = Duration.zero;
  bool _isRecording = false;
  bool _isCancelArmed = false;
  bool _showCancelFeedback = false;
  bool _isPlaying = false;
  bool _removeExisting = false;
  double _recordDragOffset = 0;

  bool get _hasAudio => _audioPath != null || _existingUrl != null;

  @override
  void initState() {
    super.initState();
    _existingUrl = widget.initialUrl;
    _recordedDuration = widget.initialDuration;
    _positionSubscription = _player.onPositionChanged.listen((position) {
      if (mounted) {
        setState(() => _playbackPosition = position);
      }
    });
    _completeSubscription = _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _playbackPosition = Duration.zero;
        });
      }
    });
  }

  @override
  void didUpdateWidget(covariant AudioDescriptionField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.resetToken != oldWidget.resetToken) {
      _discardAudio(notifyParent: false);
    }
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _positionSubscription?.cancel();
    _completeSubscription?.cancel();
    if (_isRecording) {
      unawaited(_recorder.stop().catchError((_) => null));
    }
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _deleteLocalFile(String path) async {
    try {
      await File(path).delete();
    } catch (_) {
      // The temp file may already be gone.
    }
  }

  Future<void> _startRecording(PointerDownEvent event) async {
    if (widget.isDisabled || _isRecording) {
      return;
    }

    final permission = await device_permissions.Permission.microphone.request();
    if (!permission.isGranted || !await _recorder.hasPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone access is needed')),
        );
      }
      return;
    }

    await _player.stop();
    final oldPath = _audioPath;
    if (oldPath != null) {
      await _deleteLocalFile(oldPath);
    }
    final tempDir = await getTemporaryDirectory();
    final path =
        '${tempDir.path}/audio_description_edit_${DateTime.now().microsecondsSinceEpoch}.m4a';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 64000,
        sampleRate: 44100,
      ),
      path: path,
    );

    _recordTimer?.cancel();
    setState(() {
      _audioPath = null;
      _waveSamples = const [];
      _recordElapsed = Duration.zero;
      _recordedDuration = Duration.zero;
      _playbackPosition = Duration.zero;
      _isRecording = true;
      _isCancelArmed = false;
      _showCancelFeedback = false;
      _isPlaying = false;
      _removeExisting = false;
      _recordDragOffset = 0;
    });

    _recordTimer = Timer.periodic(const Duration(milliseconds: 200), (_) async {
      if (!mounted) {
        return;
      }
      final waveSamples = List<double>.from(_waveSamples);
      waveSamples.add(await _readWaveSample(waveSamples.length));
      if (waveSamples.length > 42) {
        waveSamples.removeAt(0);
      }
      final nextElapsed = _recordElapsed + const Duration(milliseconds: 200);
      if (nextElapsed >= _maxDuration) {
        _finishRecording(cancel: false);
        return;
      }
      setState(() {
        _recordElapsed = nextElapsed;
        _waveSamples = waveSamples;
      });
    });
  }

  Future<double> _readWaveSample(int index) async {
    try {
      final amplitude = await _recorder.getAmplitude();
      final current = amplitude.current;
      if (current.isFinite) {
        return ((current + 45) / 45).clamp(0.08, 1.0);
      }
    } catch (_) {}
    return (0.25 + (math.sin(index * 1.7).abs() * 0.75)).clamp(0.08, 1.0);
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!_isRecording) {
      return;
    }
    final dragOffset = event.localPosition.dx.clamp(_cancelSlideDistance, 0.0);
    final shouldCancel = dragOffset <= _cancelSlideDistance;
    setState(() {
      _recordDragOffset = dragOffset;
      _isCancelArmed = shouldCancel;
    });
  }

  Future<void> _handlePointerUp(PointerUpEvent event) async {
    if (_isRecording) {
      await _finishRecording(cancel: _isCancelArmed);
    }
  }

  Future<void> _finishRecording({required bool cancel}) async {
    _recordTimer?.cancel();
    _recordTimer = null;
    final elapsed = _recordElapsed;
    final path = await _recorder.stop();
    if (!mounted) {
      return;
    }

    if (cancel || path == null || elapsed < const Duration(milliseconds: 500)) {
      if (path != null) {
        await _deleteLocalFile(path);
      }
      setState(() {
        _isRecording = false;
        _isCancelArmed = false;
        _showCancelFeedback = true;
        _recordElapsed = Duration.zero;
        _recordedDuration = Duration.zero;
        _playbackPosition = Duration.zero;
        _audioPath = null;
        _waveSamples = const [];
        _recordDragOffset = 0;
      });
      Future<void>.delayed(const Duration(milliseconds: 820), () {
        if (mounted) {
          setState(() => _showCancelFeedback = false);
        }
      });
      widget.onChanged(null, Duration.zero, false);
      return;
    }

    final shouldRemoveExisting = _existingUrl != null;
    setState(() {
      _isRecording = false;
      _isCancelArmed = false;
      _showCancelFeedback = false;
      _recordedDuration = elapsed > _maxDuration ? _maxDuration : elapsed;
      _playbackPosition = Duration.zero;
      _recordElapsed = Duration.zero;
      _audioPath = path;
      _existingUrl = null;
      _removeExisting = shouldRemoveExisting;
      _waveSamples = _waveSamples.isEmpty ? _fallbackWaveSamples() : _waveSamples;
      _recordDragOffset = 0;
    });
    widget.onChanged(path, _recordedDuration, shouldRemoveExisting);
  }

  List<double> _fallbackWaveSamples() {
    return List<double>.generate(
      34,
      (index) => (0.22 + math.sin(index * 0.82).abs() * 0.78).clamp(0.08, 1.0),
    );
  }

  Future<void> _togglePlayback() async {
    if (widget.isDisabled) {
      return;
    }
    if (_isPlaying) {
      await _player.pause();
      if (mounted) {
        setState(() => _isPlaying = false);
      }
      return;
    }
    final path = _audioPath;
    if (path != null) {
      await _player.play(DeviceFileSource(path));
    } else {
      final url = _existingUrl;
      if (url == null) {
        return;
      }
      await _player.play(UrlSource(url));
    }
    if (mounted) {
      setState(() {
        _isPlaying = true;
        _playbackPosition = Duration.zero;
      });
    }
  }

  Future<void> _discardAudio({bool notifyParent = true}) async {
    final path = _audioPath;
    await _player.stop();
    if (path != null) {
      await _deleteLocalFile(path);
    }
    final shouldRemoveExisting = _existingUrl != null || _removeExisting;
    if (mounted) {
      setState(() {
        _audioPath = null;
        _existingUrl = null;
        _waveSamples = const [];
        _recordedDuration = Duration.zero;
        _playbackPosition = Duration.zero;
        _isPlaying = false;
        _removeExisting = shouldRemoveExisting;
      });
    }
    if (notifyParent) {
      widget.onChanged(null, Duration.zero, shouldRemoveExisting);
    }
  }

  String _formatDuration(Duration duration) {
    final seconds = duration.inSeconds.clamp(0, 30);
    return '0:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final cancelProgress = (_recordDragOffset.abs() /
            _cancelSlideDistance.abs())
        .clamp(0.0, 1.0);
    final cancelHintOffset = -0.28 * cancelProgress;
    final cancelHintOpacity =
        _isRecording ? (1 - (cancelProgress * 0.75)).clamp(0.25, 1.0) : 1.0;

    return SizedBox(
      height: 70,
      child: InputDecorator(
        isFocused: _isRecording || _showCancelFeedback,
        isEmpty: !_hasAudio && !_isRecording && !_showCancelFeedback,
        decoration: InputDecoration(
          filled: true,
          fillColor: widget.isDisabled ? Colors.grey.shade100 : Colors.white,
          labelText: widget.label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          constraints: const BoxConstraints(minHeight: 70, maxHeight: 70),
        ),
        child: Row(
          children: [
            if (_isRecording)
              Text(
                '${_formatDuration(_recordElapsed)} / ${_formatDuration(_maxDuration)}',
                style: const TextStyle(
                  color: Colors.red,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              )
            else if (_hasAudio)
              Container(
                width: 52,
                height: 40,
                alignment: Alignment.center,
                child: IconButton(
                  onPressed: _togglePlayback,
                  icon: Icon(
                    _isPlaying ? Icons.pause_circle : Icons.play_circle_fill,
                    color: const Color(0xFFFF7801),
                    size: 36,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                ),
              )
            else
              const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(left: _isRecording ? 24 : 0),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: _showCancelFeedback
                      ? TweenAnimationBuilder<double>(
                          key: const ValueKey('cancel-feedback'),
                          tween: Tween(begin: 0.0, end: 1.0),
                          duration: const Duration(milliseconds: 720),
                          curve: Curves.easeInOut,
                          builder: (context, value, child) {
                            final lift = value < 0.45
                                ? -44 * (value / 0.45)
                                : -44 + (52 * ((value - 0.45) / 0.55));
                            final fade = value < 0.72
                                ? 1.0
                                : (1 - ((value - 0.72) / 0.28))
                                      .clamp(0.0, 1.0);
                            final micScale = value < 0.45
                                ? 1.0
                                : (1 - (0.25 * ((value - 0.45) / 0.55)));

                            return Opacity(
                              opacity: fade,
                              child: SizedBox(
                                height: 40,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: SizedBox(
                                    width: 42,
                                    height: 40,
                                    child: OverflowBox(
                                      maxHeight: 92,
                                      alignment: Alignment.bottomLeft,
                                      child: SizedBox(
                                        width: 42,
                                        height: 72,
                                        child: Stack(
                                      clipBehavior: Clip.none,
                                      alignment: Alignment.bottomCenter,
                                      children: [
                                        const Positioned(
                                          bottom: 2,
                                          child: Icon(
                                            Icons.delete,
                                            color: Color(0xFF606060),
                                            size: 22,
                                          ),
                                        ),
                                        Transform.translate(
                                          offset: Offset(0, lift),
                                          child: Transform.scale(
                                            scale: micScale,
                                            child: const CircleAvatar(
                                              radius: 10,
                                              backgroundColor: Colors.red,
                                              child: Icon(
                                                Icons.mic,
                                                color: Colors.white,
                                                size: 12,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        )
                      : _hasAudio
                          ? Row(
                              key: const ValueKey('waveform'),
                              children: [
                                Expanded(
                                  child: SizedBox(
                                    height: 34,
                                    child: _AudioWaveform(
                                      samples: _waveSamples,
                                      progress: _recordedDuration.inMilliseconds ==
                                              0
                                          ? 0
                                          : (_playbackPosition.inMilliseconds /
                                                _recordedDuration.inMilliseconds)
                                              .clamp(0.0, 1.0),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _formatDuration(_recordedDuration),
                                  style: const TextStyle(
                                    color: Colors.black87,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            )
                          : AnimatedSlide(
                              key: ValueKey(_isRecording ? 'recording' : 'idle'),
                              offset: Offset(cancelHintOffset, 0),
                              duration: const Duration(milliseconds: 90),
                              curve: Curves.easeOut,
                              child: AnimatedOpacity(
                                opacity: cancelHintOpacity,
                                duration: const Duration(milliseconds: 90),
                                child: Text(
                                  _isRecording
                                      ? (_isCancelArmed
                                            ? 'Release to cancel'
                                            : '<<< Slide to Cancel')
                                      : '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: _isRecording
                                      ? TextAlign.right
                                      : TextAlign.left,
                                  style: TextStyle(
                                    color: _isRecording && _isCancelArmed
                                        ? Colors.red
                                        : Colors.grey.shade700,
                                    fontSize: 15,
                                    fontWeight: _hasAudio || _isRecording
                                        ? FontWeight.w700
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                            ),
                ),
              ),
            ),
            if (_hasAudio)
              GestureDetector(
                onTap: widget.isDisabled ? null : _discardAudio,
                child: Container(
                  width: 52,
                  height: 40,
                  alignment: Alignment.center,
                  child: const CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.red,
                    child: Icon(Icons.close, color: Colors.white, size: 22),
                  ),
                ),
              )
            else
              Listener(
                onPointerDown: _startRecording,
                onPointerMove: _handlePointerMove,
                onPointerUp: _handlePointerUp,
                onPointerCancel: (_) {
                  if (_isRecording) {
                    _finishRecording(cancel: true);
                  }
                },
                child: Transform.translate(
                  offset: const Offset(8, 0),
                  child: Container(
                    width: 52,
                    height: 40,
                    alignment: Alignment.center,
                    child: OverflowBox(
                      maxWidth: 88,
                      maxHeight: 88,
                      child: CircleAvatar(
                        radius: _isRecording ? 44 : 18,
                        backgroundColor: _isRecording
                            ? Colors.red
                            : const Color(0xFFFF7801),
                        child: Icon(
                          Icons.mic,
                          color: Colors.white,
                          size: _isRecording ? 40 : 22,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AudioWaveform extends StatelessWidget {
  const _AudioWaveform({required this.samples, required this.progress});

  final List<double> samples;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _AudioWaveformPainter(samples, progress),
      size: Size.infinite,
    );
  }
}

class _AudioWaveformPainter extends CustomPainter {
  const _AudioWaveformPainter(this.samples, this.progress);

  final List<double> samples;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }
    final paint = Paint()
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    final barCount = (size.width / 4).floor().clamp(22, 44).toInt();
    final centerY = size.height / 2;
    final usableHeight = size.height - 4;
    final playedBars = (barCount * progress.clamp(0.0, 1.0)).round();

    for (var index = 0; index < barCount; index++) {
      paint.color = index < playedBars
          ? const Color(0xFFFF7801)
          : const Color(0xFF111820);
      final sample = samples.isEmpty
          ? (0.25 + math.sin(index * 0.82).abs() * 0.75)
          : samples[(index * samples.length / barCount).floor()];
      final barHeight = (4 + (usableHeight * sample))
          .clamp(5.0, usableHeight)
          .toDouble();
      final x = (index / (barCount - 1)) * size.width;
      canvas.drawLine(
        Offset(x, centerY - barHeight / 2),
        Offset(x, centerY + barHeight / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AudioWaveformPainter oldDelegate) {
    return oldDelegate.samples != samples || oldDelegate.progress != progress;
  }
}
