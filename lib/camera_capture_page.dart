import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class CapturedMedia {
  const CapturedMedia({required this.file, required this.type});

  final File file;
  final String type;

  bool get isVideo => type == 'video';
}

class CameraCapturePage extends StatefulWidget {
  const CameraCapturePage({super.key});

  @override
  State<CameraCapturePage> createState() => _CameraCapturePageState();
}

class _CameraCapturePageState extends State<CameraCapturePage> {
  CameraController? _controller;
  Future<void>? _initializeCamera;
  VideoPlayerController? _previewController;
  File? _previewVideoFile;
  bool _isRecording = false;
  bool _isFinishingCapture = false;
  Timer? _holdTimer;
  double _minZoom = 1;
  double _maxZoom = 1;
  double _currentZoom = 1;
  double _recordingStartZoom = 1;
  double? _pressStartY;

  @override
  void initState() {
    super.initState();
    _initializeCamera = _setupCamera();
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _previewController?.dispose();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _setupCamera() async {
    final cameras = await availableCameras();
    final backCamera = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    final controller = CameraController(
      backCamera,
      ResolutionPreset.medium,
      enableAudio: true,
    );
    _controller = controller;
    await controller.initialize();
    _minZoom = await controller.getMinZoomLevel();
    _maxZoom = await controller.getMaxZoomLevel();
    _currentZoom = _minZoom;
    await controller.setZoomLevel(_currentZoom);
  }

  void _onCapturePressStart(TapDownDetails details) {
    _holdTimer?.cancel();
    _pressStartY = details.globalPosition.dy;
    _recordingStartZoom = _currentZoom;
    _holdTimer = Timer(const Duration(milliseconds: 280), () {
      _startVideoRecording();
    });
  }

  Future<void> _onCapturePressEnd() async {
    final wasRecording = _isRecording;
    _holdTimer?.cancel();
    _pressStartY = null;

    if (wasRecording) {
      await _stopVideoRecording();
      return;
    }

    await _takePhoto();
  }

  void _onCaptureCancel() {
    _holdTimer?.cancel();
    _pressStartY = null;
  }

  void _onCaptureMove(PointerMoveEvent event) {
    final controller = _controller;
    final pressStartY = _pressStartY;
    if (controller == null ||
        !controller.value.isInitialized ||
        !_isRecording ||
        pressStartY == null) {
      return;
    }

    final dragUpDistance = pressStartY - event.position.dy;
    final zoomRange = _maxZoom - _minZoom;
    final zoomDelta = (dragUpDistance / 180).clamp(-1.0, 1.0) * zoomRange;
    final nextZoom = (_recordingStartZoom + zoomDelta).clamp(
      _minZoom,
      _maxZoom,
    );

    if ((nextZoom - _currentZoom).abs() < 0.03) {
      return;
    }
    _currentZoom = nextZoom;
    controller.setZoomLevel(nextZoom);
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _takePhoto() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        _isFinishingCapture) {
      return;
    }

    setState(() => _isFinishingCapture = true);
    try {
      final file = await controller.takePicture();
      if (!mounted) {
        return;
      }
      Navigator.pop(
        context,
        CapturedMedia(file: File(file.path), type: 'image'),
      );
    } finally {
      if (mounted) {
        setState(() => _isFinishingCapture = false);
      }
    }
  }

  Future<void> _startVideoRecording() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        _isRecording ||
        _isFinishingCapture) {
      return;
    }

    await controller.startVideoRecording();
    if (mounted) {
      setState(() {
        _isRecording = true;
        _recordingStartZoom = _currentZoom;
      });
    }
  }

  Future<void> _stopVideoRecording() async {
    final controller = _controller;
    if (controller == null || !_isRecording || _isFinishingCapture) {
      return;
    }

    setState(() => _isFinishingCapture = true);
    try {
      final file = await controller.stopVideoRecording();
      if (!mounted) {
        return;
      }
      await _showVideoPreview(File(file.path));
    } finally {
      if (mounted) {
        setState(() {
          _isRecording = false;
          _isFinishingCapture = false;
        });
      }
    }
  }

  Future<void> _showVideoPreview(File file) async {
    await _previewController?.dispose();
    final previewController = VideoPlayerController.file(file);
    await previewController.initialize();
    await previewController.setLooping(true);
    await previewController.play();
    if (!mounted) {
      await previewController.dispose();
      return;
    }
    setState(() {
      _previewVideoFile = file;
      _previewController = previewController;
    });
  }

  Future<void> _discardVideoPreview() async {
    final file = _previewVideoFile;
    await _previewController?.dispose();
    if (file != null && file.existsSync()) {
      try {
        file.deleteSync();
      } catch (_) {
        // Temporary camera file cleanup is best-effort.
      }
    }
    if (mounted) {
      setState(() {
        _previewVideoFile = null;
        _previewController = null;
      });
    }
  }

  void _acceptVideoPreview() {
    final file = _previewVideoFile;
    if (file == null) {
      return;
    }
    Navigator.pop(context, CapturedMedia(file: file, type: 'video'));
  }

  @override
  Widget build(BuildContext context) {
    final previewVideoFile = _previewVideoFile;
    final previewController = _previewController;
    if (previewVideoFile != null && previewController != null) {
      return _VideoPreviewScaffold(
        controller: previewController,
        onDiscard: _discardVideoPreview,
        onAccept: _acceptVideoPreview,
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: FutureBuilder<void>(
        future: _initializeCamera,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || _controller == null) {
            return Center(
              child: Text(
                'Camera could not be opened',
                style: TextStyle(color: Colors.grey[300]),
              ),
            );
          }

          return Stack(
            children: [
              Positioned.fill(child: CameraPreview(_controller!)),
              SafeArea(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: IconButton.filled(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 44,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _isRecording ? 'Release to stop' : 'Tap photo, hold video',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Listener(
                      onPointerMove: _onCaptureMove,
                      onPointerUp: (_) => _onCapturePressEnd(),
                      onPointerCancel: (_) => _onCaptureCancel(),
                      child: GestureDetector(
                        onTapDown: _onCapturePressStart,
                        onTapCancel: _onCaptureCancel,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          width: _isRecording ? 86 : 74,
                          height: _isRecording ? 86 : 74,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 5),
                            color: _isRecording
                                ? Colors.red
                                : Colors.white.withValues(alpha: 0.18),
                          ),
                          child: Center(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              width: _isRecording ? 34 : 52,
                              height: _isRecording ? 34 : 52,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: _isRecording
                                    ? BoxShape.rectangle
                                    : BoxShape.circle,
                                borderRadius: _isRecording
                                    ? BorderRadius.circular(8)
                                    : null,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_isRecording) ...[
                      const SizedBox(height: 12),
                      Text(
                        '${_currentZoom.toStringAsFixed(1)}x',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _VideoPreviewScaffold extends StatelessWidget {
  const _VideoPreviewScaffold({
    required this.controller,
    required this.onDiscard,
    required this.onAccept,
  });

  final VideoPlayerController controller;
  final VoidCallback onDiscard;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: controller.value.size.width,
                height: controller.value.size.height,
                child: VideoPlayer(controller),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: IconButton.filled(
                onPressed: onDiscard,
                icon: const Icon(Icons.close),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 44,
            child: SafeArea(
              child: Center(
                child: Material(
                  color: const Color(0xFF25D366),
                  shape: const CircleBorder(),
                  elevation: 5,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onAccept,
                    child: const SizedBox(
                      width: 64,
                      height: 64,
                      child: Icon(Icons.check, color: Colors.white, size: 34),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
