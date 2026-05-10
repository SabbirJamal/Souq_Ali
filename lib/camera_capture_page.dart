import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:video_trimmer/video_trimmer.dart';
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
  static const Duration _maxRecordingDuration = Duration(seconds: 60);

  CameraController? _controller;
  Future<void>? _initializeCamera;
  VideoPlayerController? _previewController;
  File? _previewVideoFile;
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
      ResolutionPreset.high,
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

  Future<void> _openVideoTrimmer() async {
    final file = _previewVideoFile;
    if (file == null) {
      return;
    }
    await _previewController?.pause();
    final trimmedFile = await Navigator.push<File>(
      context,
      MaterialPageRoute(
        builder: (_) => _VideoTrimPage(file: file),
      ),
    );
    if (trimmedFile == null || !mounted) {
      await _previewController?.play();
      return;
    }
    await _showVideoPreview(trimmedFile);
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
        onTrim: _openVideoTrimmer,
        onCrop: () => _showCropUnavailable(context),
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

class _VideoPreviewScaffold extends StatelessWidget {
  const _VideoPreviewScaffold({
    required this.controller,
    required this.onDiscard,
    required this.onAccept,
    required this.onTrim,
    required this.onCrop,
  });

  final VideoPlayerController controller;
  final VoidCallback onDiscard;
  final VoidCallback onAccept;
  final VoidCallback onTrim;
  final VoidCallback onCrop;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: _VideoPreviewCover(controller: controller),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  IconButton.filled(
                    onPressed: onDiscard,
                    icon: const Icon(Icons.close),
                  ),
                  const Spacer(),
                  _RoundToolButton(
                    icon: Icons.crop_rotate,
                    onTap: onCrop,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            top: 78,
            child: SafeArea(
              child: GestureDetector(
                onTap: onTrim,
                child: Container(
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.62),
                    borderRadius: BorderRadius.circular(2),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.46),
                    ),
                  ),
                  child: Row(
                    children: const [
                      SizedBox(width: 8),
                      Icon(Icons.chevron_left, color: Colors.white, size: 30),
                      Expanded(
                        child: Divider(color: Colors.white70, thickness: 3),
                      ),
                      Icon(Icons.chevron_right, color: Colors.white, size: 30),
                      SizedBox(width: 8),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 24,
            bottom: 44,
            child: SafeArea(
              child: _AcceptButton(onTap: onAccept),
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoPreviewCover extends StatelessWidget {
  const _VideoPreviewCover({required this.controller});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final videoSize = controller.value.size;
    if (videoSize.width == 0 || videoSize.height == 0) {
      return const ColoredBox(color: Colors.black);
    }

    final videoAspectRatio = videoSize.width / videoSize.height;
    final screenAspectRatio = size.width / size.height;
    final scale = videoAspectRatio > screenAspectRatio
        ? size.height / videoSize.height
        : size.width / videoSize.width;

    return ClipRect(
      child: Center(
        child: SizedBox(
          width: videoSize.width * scale,
          height: videoSize.height * scale,
          child: VideoPlayer(controller),
        ),
      ),
    );
  }
}

class _VideoTrimPage extends StatefulWidget {
  const _VideoTrimPage({required this.file});

  final File file;

  @override
  State<_VideoTrimPage> createState() => _VideoTrimPageState();
}

class _VideoTrimPageState extends State<_VideoTrimPage> {
  final Trimmer _trimmer = Trimmer();
  double _startValue = 0;
  double _endValue = 0;
  bool _isSaving = false;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _trimmer.loadVideo(videoFile: widget.file);
  }

  Future<void> _saveTrimmedVideo() async {
    if (_isSaving) {
      return;
    }
    setState(() => _isSaving = true);
    await _trimmer.saveTrimmedVideo(
      startValue: _startValue,
      endValue: _endValue,
      videoFolderName: 'BizsooqTrimmed',
      onSave: (outputPath) {
        if (!mounted) {
          return;
        }
        setState(() => _isSaving = false);
        if (outputPath == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not trim video')),
          );
          return;
        }
        Navigator.pop(context, File(outputPath));
      },
    );
  }

  Future<void> _togglePlayback() async {
    final isPlaying = await _trimmer.videoPlaybackControl(
      startValue: _startValue,
      endValue: _endValue,
    );
    if (mounted) {
      setState(() => _isPlaying = isPlaying);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      IconButton.filled(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                      const Spacer(),
                      _RoundToolButton(
                        icon: Icons.crop_rotate,
                        onTap: () => _showCropUnavailable(context),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: TrimViewer(
                    trimmer: _trimmer,
                    viewerHeight: 54,
                    viewerWidth: MediaQuery.of(context).size.width,
                    maxVideoLength: _CameraCapturePageState
                        ._maxRecordingDuration,
                    durationStyle: DurationStyle.FORMAT_MM_SS,
                    editorProperties: const TrimEditorProperties(
                      borderPaintColor: Colors.white,
                      circlePaintColor: Colors.white,
                      scrubberPaintColor: Color(0xFF25D366),
                      borderWidth: 3,
                      borderRadius: 0,
                    ),
                    areaProperties: TrimAreaProperties.edgeBlur(
                      thumbnailQuality: 60,
                    ),
                    onChangeStart: (value) => _startValue = value,
                    onChangeEnd: (value) => _endValue = value,
                    onChangePlaybackState: (value) {
                      if (mounted) {
                        setState(() => _isPlaying = value);
                      }
                    },
                  ),
                ),
                Expanded(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      VideoViewer(trimmer: _trimmer),
                      IconButton.filled(
                        onPressed: _togglePlayback,
                        iconSize: 56,
                        icon: Icon(
                          _isPlaying ? Icons.pause : Icons.play_arrow,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_isSaving)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x99000000),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
            Positioned(
              right: 24,
              bottom: 28,
              child: _AcceptButton(onTap: _saveTrimmedVideo),
            ),
          ],
        ),
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

void _showCropUnavailable(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Video crop needs one more native export step.'),
    ),
  );
}
