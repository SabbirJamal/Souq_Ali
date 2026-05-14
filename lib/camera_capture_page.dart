import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_cropper/image_cropper.dart';

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
  static const Duration _maxRecordingDuration = Duration(seconds: 60);

  CameraController? _controller;
  Future<void>? _initializeCamera;
  bool _isRecording = false;
  bool _isFinishingCapture = false;
  Timer? _holdTimer;
  Timer? _recordingLimitTimer;
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
    _recordingLimitTimer?.cancel();
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
      ResolutionPreset.high,
      enableAudio: true,
    );
    _controller = controller;
    await controller.initialize();
    await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
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
      await _showImagePreview(File(file.path));
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
    _recordingLimitTimer?.cancel();
    _recordingLimitTimer = Timer(_maxRecordingDuration, () {
      if (_isRecording && !_isFinishingCapture) {
        _stopVideoRecording();
      }
    });
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

    _recordingLimitTimer?.cancel();
    setState(() => _isFinishingCapture = true);
    try {
      final file = await controller.stopVideoRecording();
      if (!mounted) {
        return;
      }
      Navigator.pop(
        context,
        CapturedMedia(file: File(file.path), type: 'video'),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isRecording = false;
          _isFinishingCapture = false;
        });
      }
    }
  }

  Future<void> _showImagePreview(File file) async {
    if (!mounted) {
      return;
    }
    final result = await Navigator.push<CapturedMedia>(
      context,
      MaterialPageRoute(
        builder: (_) => _ImagePreviewPage(file: file),
      ),
    );
    if (!mounted) {
      return;
    }
    if (result != null) {
      Navigator.pop(context, result);
    }
  }

  @override
  Widget build(BuildContext context) {
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
              Positioned.fill(child: _CameraPreviewCover(controller: _controller!)),
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

class _CameraPreviewCover extends StatelessWidget {
  const _CameraPreviewCover({required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final previewSize = controller.value.previewSize;

    if (previewSize == null) {
      return CameraPreview(controller);
    }

    final previewAspectRatio = previewSize.height / previewSize.width;
    final screenAspectRatio = size.width / size.height;
    final scale = previewAspectRatio / screenAspectRatio;

    return ClipRect(
      child: Transform.scale(
        scale: scale < 1 ? 1 / scale : scale,
        alignment: Alignment.center,
        child: Center(
          child: AspectRatio(
            aspectRatio: previewAspectRatio,
            child: CameraPreview(controller),
          ),
        ),
      ),
    );
  }
}

class _ImagePreviewPage extends StatefulWidget {
  const _ImagePreviewPage({required this.file});

  final File file;

  @override
  State<_ImagePreviewPage> createState() => _ImagePreviewPageState();
}

class _ImagePreviewPageState extends State<_ImagePreviewPage> {
  late File _file;

  @override
  void initState() {
    super.initState();
    _file = widget.file;
  }

  Future<void> _cropImage() async {
    final croppedFile = await ImageCropper().cropImage(
      sourcePath: _file.path,
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 92,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop',
          toolbarColor: Colors.black,
          toolbarWidgetColor: Colors.white,
          activeControlsWidgetColor: const Color(0xFF25D366),
          initAspectRatio: CropAspectRatioPreset.original,
          lockAspectRatio: false,
          aspectRatioPresets: [
            CropAspectRatioPreset.original,
            CropAspectRatioPreset.square,
            CropAspectRatioPreset.ratio3x2,
            CropAspectRatioPreset.ratio4x3,
            CropAspectRatioPreset.ratio16x9,
          ],
        ),
        IOSUiSettings(
          title: 'Crop',
          aspectRatioPresets: [
            CropAspectRatioPreset.original,
            CropAspectRatioPreset.square,
            CropAspectRatioPreset.ratio3x2,
            CropAspectRatioPreset.ratio4x3,
            CropAspectRatioPreset.ratio16x9,
          ],
        ),
      ],
    );

    if (croppedFile == null || !mounted) {
      return;
    }
    setState(() => _file = File(croppedFile.path));
  }

  void _accept() {
    Navigator.pop(context, CapturedMedia(file: _file, type: 'image'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: Center(
                child: Image.file(
                  _file,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  IconButton.filled(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                  const Spacer(),
                  _RoundToolButton(
                    icon: Icons.crop_rotate,
                    onTap: _cropImage,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 24,
            bottom: 44,
            child: SafeArea(
              child: _AcceptButton(onTap: _accept),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundToolButton extends StatelessWidget {
  const _RoundToolButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.18),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 54,
          height: 54,
          child: Icon(icon, color: Colors.white, size: 28),
        ),
      ),
    );
  }
}

class _AcceptButton extends StatelessWidget {
  const _AcceptButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF25D366),
      shape: const CircleBorder(),
      elevation: 5,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const SizedBox(
          width: 64,
          height: 64,
          child: Icon(Icons.check, color: Colors.white, size: 34),
        ),
      ),
    );
  }
}
