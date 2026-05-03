import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

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
  bool _isRecording = false;
  bool _isFinishingCapture = false;
  Timer? _holdTimer;

  @override
  void initState() {
    super.initState();
    _initializeCamera = _setupCamera();
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
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
  }

  void _onCapturePressStart() {
    _holdTimer?.cancel();
    _holdTimer = Timer(const Duration(milliseconds: 280), () {
      _startVideoRecording();
    });
  }

  Future<void> _onCapturePressEnd() async {
    final wasRecording = _isRecording;
    _holdTimer?.cancel();

    if (wasRecording) {
      await _stopVideoRecording();
      return;
    }

    await _takePhoto();
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
      setState(() => _isRecording = true);
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
                    GestureDetector(
                      onTapDown: (_) => _onCapturePressStart(),
                      onTapUp: (_) => _onCapturePressEnd(),
                      onTapCancel: () => _holdTimer?.cancel(),
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
                              color: _isRecording ? Colors.white : Colors.white,
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
