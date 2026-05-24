import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';

class CapturedMedia {
  const CapturedMedia({required this.file, required this.type});

  final File file;
  final String type;

  bool get isVideo => type == 'video';
}

enum CameraCaptureAction { openGallery }

class CameraCapturePage extends StatefulWidget {
  const CameraCapturePage({super.key});

  @override
  State<CameraCapturePage> createState() => _CameraCapturePageState();
}

class _CameraCapturePageState extends State<CameraCapturePage> {
  static const Duration _maxRecordingDuration = Duration(seconds: 60);

  CameraController? _controller;
  Future<void>? _initializeCamera;
  List<CameraDescription> _cameras = const [];
  int _cameraIndex = 0;
  bool _isFlashOn = false;
  bool _isRecording = false;
  bool _isFinishingCapture = false;
  Timer? _holdTimer;
  Timer? _recordingLimitTimer;
  double _minZoom = 1;
  double _maxZoom = 1;
  double _currentZoom = 1;
  double _recordingStartZoom = 1;
  double? _pressStartY;
  List<AssetEntity> _recentAssets = const [];

  @override
  void initState() {
    super.initState();
    _initializeCamera = _setupCamera();
    _loadRecentAssets();
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _recordingLimitTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _setupCamera() async {
    _cameras = await availableCameras();
    final backCamera = _cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.back,
      orElse: () => _cameras.first,
    );
    _cameraIndex = _cameras.indexOf(backCamera);

    await _setCameraController(backCamera);
  }

  Future<void> _setCameraController(CameraDescription camera) async {
    await _controller?.dispose();
    final controller = CameraController(
      camera,
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
    _isFlashOn = false;
  }

  Future<void> _toggleCamera() async {
    if (_cameras.length < 2 || _isRecording || _isFinishingCapture) {
      return;
    }

    setState(() {
      _cameraIndex = (_cameraIndex + 1) % _cameras.length;
      _initializeCamera = _setCameraController(_cameras[_cameraIndex]);
    });
  }

  Future<void> _toggleFlash() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        _isRecording ||
        _isFinishingCapture) {
      return;
    }

    try {
      final nextFlashState = !_isFlashOn;
      await controller.setFlashMode(
        nextFlashState ? FlashMode.torch : FlashMode.off,
      );
      if (mounted) {
        setState(() => _isFlashOn = nextFlashState);
      }
    } on CameraException {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Flash is not available on this camera')),
      );
    }
  }

  Future<void> _loadRecentAssets() async {
    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.hasAccess) {
      return;
    }
    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.common,
      onlyAll: true,
    );
    if (albums.isEmpty) {
      return;
    }
    final assets = await albums.first.getAssetListPaged(page: 0, size: 12);
    if (mounted) {
      setState(() => _recentAssets = assets);
    }
  }

  Future<void> _selectRecentAsset(AssetEntity asset) async {
    if (asset.type == AssetType.video && asset.duration > 60) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Video cannot be more than 1 minute')),
      );
      return;
    }
    final file = await asset.fileWithSubtype ?? await asset.file;
    if (file == null || !mounted) {
      return;
    }
    Navigator.pop(
      context,
      CapturedMedia(
        file: file,
        type: asset.type == AssetType.video ? 'video' : 'image',
      ),
    );
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
    if (!mounted) {
      return;
    }
    final result = await Navigator.push<CapturedMedia>(
      context,
      MaterialPageRoute(
        builder: (_) => _VideoPreviewPage(file: file),
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
              Positioned.fill(
                child: _CameraPreviewCover(controller: _controller!),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.18),
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.58),
                        ],
                        stops: const [0, 0.48, 1],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 14,
                left: 14,
                right: 14,
                child: SafeArea(
                  bottom: false,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _FloatingCircleButton(
                        icon: Icons.close,
                        onTap: () => Navigator.pop(context),
                      ),
                      _FloatingCircleButton(
                        icon: _isFlashOn ? Icons.flash_on : Icons.flash_off,
                        onTap: _toggleFlash,
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_recentAssets.isNotEmpty) ...[
                          _RecentMediaStrip(
                            assets: _recentAssets,
                            onAssetTap: _selectRecentAsset,
                          ),
                          const SizedBox(height: 10),
                          _LatestMediaPreview(
                            asset: _recentAssets.first,
                            onTap: () => _selectRecentAsset(
                              _recentAssets.first,
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (_isRecording) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${_currentZoom.toStringAsFixed(1)}x',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 28),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _FloatingCircleButton(
                                icon: Icons.photo_library_outlined,
                                size: 52,
                                onTap: _isRecording || _isFinishingCapture
                                    ? null
                                    : () => Navigator.pop(
                                          context,
                                          CameraCaptureAction.openGallery,
                                        ),
                              ),
                              Listener(
                                onPointerMove: _onCaptureMove,
                                onPointerUp: (_) => _onCapturePressEnd(),
                                onPointerCancel: (_) => _onCaptureCancel(),
                                child: GestureDetector(
                                  onTapDown: _onCapturePressStart,
                                  onTapCancel: _onCaptureCancel,
                                  child: _CaptureButton(
                                    isRecording: _isRecording,
                                    isBusy: _isFinishingCapture,
                                  ),
                                ),
                              ),
                              _FloatingCircleButton(
                                icon: Icons.cameraswitch_outlined,
                                size: 52,
                                onTap: _isRecording || _isFinishingCapture
                                    ? null
                                    : _toggleCamera,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _CameraModeText(
                              text: 'Video',
                              active: _isRecording,
                            ),
                            const SizedBox(width: 18),
                            _CameraModeText(
                              text: 'Photo',
                              active: !_isRecording,
                            ),
                            const SizedBox(width: 18),
                            const _CameraModeText(
                              text: 'Video note',
                              active: false,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
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

class _RecentMediaStrip extends StatelessWidget {
  const _RecentMediaStrip({
    required this.assets,
    required this.onAssetTap,
  });

  final List<AssetEntity> assets;
  final ValueChanged<AssetEntity> onAssetTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 74,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        itemCount: assets.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final asset = assets[index];
          return GestureDetector(
            onTap: () => onAssetTap(asset),
            child: Stack(
              fit: StackFit.expand,
              children: [
                SizedBox(
                  width: 74,
                  height: 74,
                  child: FutureBuilder<Uint8List?>(
                    future: asset.thumbnailDataWithSize(
                      const ThumbnailSize.square(180),
                    ),
                    builder: (context, snapshot) {
                      final bytes = snapshot.data;
                      if (bytes == null) {
                        return Container(color: Colors.black38);
                      }
                      return Image.memory(bytes, fit: BoxFit.cover);
                    },
                  ),
                ),
                if (asset.type == AssetType.video)
                  const Positioned(
                    left: 5,
                    bottom: 4,
                    child: Icon(
                      Icons.videocam,
                      color: Colors.white,
                      size: 17,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _LatestMediaPreview extends StatelessWidget {
  const _LatestMediaPreview({
    required this.asset,
    required this.onTap,
  });

  final AssetEntity asset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.85),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 58,
            height: 78,
            child: Stack(
              fit: StackFit.expand,
              children: [
                FutureBuilder<Uint8List?>(
                  future: asset.thumbnailDataWithSize(
                    const ThumbnailSize.square(220),
                  ),
                  builder: (context, snapshot) {
                    final bytes = snapshot.data;
                    if (bytes == null) {
                      return Container(color: Colors.black45);
                    }
                    return Image.memory(bytes, fit: BoxFit.cover);
                  },
                ),
                if (asset.type == AssetType.video)
                  const Center(
                    child: Icon(
                      Icons.play_circle_fill,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FloatingCircleButton extends StatelessWidget {
  const _FloatingCircleButton({
    required this.icon,
    required this.onTap,
    this.size = 50,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: onTap == null
          ? Colors.black26
          : Colors.black.withValues(alpha: 0.48),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            icon,
            color: onTap == null ? Colors.white38 : Colors.white,
            size: size * 0.48,
          ),
        ),
      ),
    );
  }
}

class _CaptureButton extends StatelessWidget {
  const _CaptureButton({
    required this.isRecording,
    required this.isBusy,
  });

  final bool isRecording;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final outerSize = isRecording ? 92.0 : 84.0;
    final innerSize = isRecording ? 34.0 : 64.0;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 140),
      opacity: isBusy ? 0.55 : 1,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: outerSize,
        height: outerSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 5),
          color: isRecording
              ? Colors.red.withValues(alpha: 0.9)
              : Colors.white.withValues(alpha: 0.16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: innerSize,
            height: innerSize,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: isRecording ? BoxShape.rectangle : BoxShape.circle,
              borderRadius: isRecording ? BorderRadius.circular(9) : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _CameraModeText extends StatelessWidget {
  const _CameraModeText({required this.text, required this.active});

  final String text;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      decoration: BoxDecoration(
        color: active ? Colors.white.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: active ? Colors.white : Colors.white70,
          fontSize: 16,
          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
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
            child: Image.file(
              _file,
              fit: BoxFit.cover,
            ),
          ),
          Positioned(
            right: 24,
            bottom: 34,
            child: SafeArea(
              child: _AcceptButton(onTap: _accept, size: 64),
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoPreviewPage extends StatefulWidget {
  const _VideoPreviewPage({required this.file});

  final File file;

  @override
  State<_VideoPreviewPage> createState() => _VideoPreviewPageState();
}

class _VideoPreviewPageState extends State<_VideoPreviewPage> {
  late final VideoPlayerController _controller;
  late final Future<void> _initializeVideo;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.file);
    _initializeVideo = _controller.initialize().then((_) {
      _controller
        ..setLooping(true)
        ..play();
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _accept(BuildContext context) {
    Navigator.pop(context, CapturedMedia(file: widget.file, type: 'video'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: FutureBuilder<void>(
              future: _initializeVideo,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done ||
                    !_controller.value.isInitialized) {
                  return const Center(child: CircularProgressIndicator());
                }
                return FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _controller.value.size.width,
                    height: _controller.value.size.height,
                    child: VideoPlayer(_controller),
                  ),
                );
              },
            ),
          ),
          Center(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _controller.value.isPlaying
                      ? _controller.pause()
                      : _controller.play();
                });
              },
              child: AnimatedOpacity(
                opacity: _controller.value.isPlaying ? 0 : 1,
                duration: const Duration(milliseconds: 180),
                child: const Icon(
                  Icons.play_circle_fill,
                  color: Colors.white70,
                  size: 86,
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
                    icon: Icons.hd,
                    onTap: () {},
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 24,
            bottom: 44,
            child: SafeArea(
              child: _AcceptButton(onTap: () => _accept(context)),
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
  const _AcceptButton({required this.onTap, this.size = 64});

  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF25D366),
      shape: const CircleBorder(),
      elevation: 5,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(Icons.check, color: Colors.white, size: size * 0.53),
        ),
      ),
    );
  }
}
