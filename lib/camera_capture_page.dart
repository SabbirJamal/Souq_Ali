import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_compress/video_compress.dart';
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

  static Future<List<CameraDescription>>? _cameraListFuture;

  static Future<List<CameraDescription>> preloadCameras() {
    return _cameraListFuture ??= availableCameras();
  }

  @override
  State<CameraCapturePage> createState() => _CameraCapturePageState();
}

class _CameraCapturePageState extends State<CameraCapturePage>
    with WidgetsBindingObserver {
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
  Timer? _recordingTickTimer;
  Duration _recordingElapsed = Duration.zero;
  double _minZoom = 1;
  double _maxZoom = 1;
  double _currentZoom = 1;
  double _recordingStartZoom = 1;
  double _pinchStartZoom = 1;
  double? _pressStartY;
  Offset? _focusPoint;
  List<AssetEntity> _recentAssets = const [];
  int _recentLoadToken = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadRecentAssets());
    _initializeCamera = _setupCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _holdTimer?.cancel();
    _recordingLimitTimer?.cancel();
    _recordingTickTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_loadRecentAssets());
    }
  }

  Future<void> _setupCamera() async {
    _cameras = await CameraCapturePage.preloadCameras();
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
      ResolutionPreset.medium,
      enableAudio: true,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    _controller = controller;
    await controller.initialize();
    await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
    _minZoom = await controller.getMinZoomLevel();
    _maxZoom = await controller.getMaxZoomLevel();
    _currentZoom = _minZoom;
    _pinchStartZoom = _currentZoom;
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
    final loadToken = ++_recentLoadToken;
    try {
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

      final assets = <AssetEntity>[];
      var page = 0;
      while (assets.length < 10 && page < 3) {
        final pageAssets = await albums.first.getAssetListPaged(
          page: page,
          size: 24,
        );
        if (pageAssets.isEmpty) {
          break;
        }
        assets.addAll(
          pageAssets.where(
            (asset) => asset.type != AssetType.video || asset.duration <= 60,
          ),
        );
        page++;
      }

      if (mounted && loadToken == _recentLoadToken) {
        setState(() => _recentAssets = assets.take(10).toList());
      }
    } catch (_) {
      if (mounted && loadToken == _recentLoadToken) {
        setState(() => _recentAssets = const []);
      }
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
    _setCameraZoom(nextZoom);
  }

  void _onPreviewScaleStart(ScaleStartDetails details) {
    if (details.pointerCount < 2) {
      return;
    }
    _pinchStartZoom = _currentZoom;
  }

  void _onPreviewScaleUpdate(ScaleUpdateDetails details) {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        details.pointerCount < 2) {
      return;
    }

    final nextZoom = (_pinchStartZoom * details.scale).clamp(
      _minZoom,
      _maxZoom,
    );
    _setCameraZoom(nextZoom);
  }

  Future<void> _onPreviewTapDown(TapDownDetails details) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    final box = context.findRenderObject() as RenderBox?;
    if (box == null) {
      return;
    }
    final localPosition = box.globalToLocal(details.globalPosition);
    final size = box.size;
    final normalizedPoint = Offset(
      (localPosition.dx / size.width).clamp(0.0, 1.0),
      (localPosition.dy / size.height).clamp(0.0, 1.0),
    );

    try {
      await controller.setFocusPoint(normalizedPoint);
      await controller.setExposurePoint(normalizedPoint);
    } on CameraException {
      // Some devices do not support tap focus/exposure points.
    }

    if (!mounted) {
      return;
    }
    setState(() => _focusPoint = localPosition);
    Future<void>.delayed(const Duration(milliseconds: 850), () {
      if (mounted && _focusPoint == localPosition) {
        setState(() => _focusPoint = null);
      }
    });
  }

  void _setCameraZoom(double zoom) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    if ((zoom - _currentZoom).abs() < 0.02) {
      return;
    }
    _currentZoom = zoom;
    controller.setZoomLevel(zoom);
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
    _recordingElapsed = Duration.zero;
    _recordingLimitTimer?.cancel();
    _recordingLimitTimer = Timer(_maxRecordingDuration, () {
      if (_isRecording && !_isFinishingCapture) {
        _stopVideoRecording();
      }
    });
    _recordingTickTimer?.cancel();
    _recordingTickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_isRecording || !mounted) {
        return;
      }
      final nextElapsed = _recordingElapsed + const Duration(seconds: 1);
      setState(() {
        _recordingElapsed = nextElapsed > _maxRecordingDuration
            ? _maxRecordingDuration
            : nextElapsed;
      });
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
    _recordingTickTimer?.cancel();
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
          _recordingElapsed = Duration.zero;
        });
      }
    }
  }

  Future<void> _showImagePreview(File file) async {
    if (!mounted) {
      return;
    }
    final controller = _controller;
    if (controller != null && controller.value.isInitialized) {
      unawaited(controller.pausePreview().catchError((_) {}));
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
      return;
    }
    if (controller != null && controller.value.isInitialized) {
      unawaited(controller.resumePreview().catchError((_) {}));
    }
  }

  Future<void> _showVideoPreview(File file) async {
    if (!mounted) {
      return;
    }
    final controller = _controller;
    if (controller != null && controller.value.isInitialized) {
      unawaited(controller.pausePreview().catchError((_) {}));
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
      return;
    }
    if (controller != null && controller.value.isInitialized) {
      unawaited(controller.resumePreview().catchError((_) {}));
    }
  }

  String _formatRecordingTime(Duration duration) {
    final totalSeconds = duration.inSeconds.clamp(
      0,
      _maxRecordingDuration.inSeconds,
    );
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
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
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: _onPreviewTapDown,
                  onScaleStart: _onPreviewScaleStart,
                  onScaleUpdate: _onPreviewScaleUpdate,
                  child: _CameraPreviewCover(controller: _controller!),
                ),
              ),
              if (_focusPoint != null)
                Positioned(
                  left: _focusPoint!.dx - 34,
                  top: _focusPoint!.dy - 34,
                  child: const _FocusRing(),
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
              if (_isRecording)
                Positioned(
                  top: 20,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    bottom: false,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _formatRecordingTime(_recordingElapsed),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
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
                        if (!_isRecording && _recentAssets.isNotEmpty) ...[
                          _RecentMediaStrip(
                            assets: _recentAssets,
                            onAssetTap: _selectRecentAsset,
                            onSwipeUp: () => Navigator.pop(
                              context,
                              CameraCaptureAction.openGallery,
                            ),
                          ),
                          const SizedBox(height: 12),
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
                                    progress:
                                        _recordingElapsed.inMilliseconds /
                                            _maxRecordingDuration
                                                .inMilliseconds,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 52,
                                child: Center(
                                  child: _ZoomIndicator(zoom: _currentZoom),
                                ),
                              ),
                            ],
                          ),
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
    required this.onSwipeUp,
  });

  final List<AssetEntity> assets;
  final ValueChanged<AssetEntity> onAssetTap;
  final VoidCallback onSwipeUp;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 78,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: assets.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final asset = assets[index];
          return SizedBox(
            width: 78,
            height: 78,
            child: GestureDetector(
              onTap: () => onAssetTap(asset),
              onVerticalDragEnd: (details) {
                final velocity = details.primaryVelocity ?? 0;
                if (velocity < -350) {
                  onSwipeUp();
                }
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  FutureBuilder<Uint8List?>(
                    future: _safeAssetThumbnail(asset),
                    builder: (context, snapshot) {
                      final bytes = snapshot.data;
                      if (bytes == null) {
                        return Container(color: Colors.black38);
                      }
                      return Image.memory(bytes, fit: BoxFit.cover);
                    },
                  ),
                  if (asset.type == AssetType.video)
                    Positioned(
                      left: 5,
                      bottom: 4,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 3,
                          ),
                          child: Icon(
                            Icons.videocam,
                            color: Colors.white,
                            size: 17,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
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

Future<Uint8List?> _safeAssetThumbnail(AssetEntity asset) async {
  try {
    return await asset.thumbnailDataWithSize(
      const ThumbnailSize.square(180),
    );
  } catch (_) {
    return null;
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

class _ZoomIndicator extends StatelessWidget {
  const _ZoomIndicator({required this.zoom});

  final double zoom;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.52),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
      ),
      child: SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: Text(
            '${zoom.toStringAsFixed(2)}x',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _FocusRing extends StatelessWidget {
  const _FocusRing();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 1.25, end: 1),
        duration: const Duration(milliseconds: 170),
        builder: (context, scale, child) {
          return Transform.scale(scale: scale, child: child);
        },
        child: Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 8,
              ),
            ],
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
    required this.progress,
  });

  final bool isRecording;
  final bool isBusy;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final outerSize = isRecording ? 100.0 : 84.0;
    final innerSize = isRecording ? 34.0 : 64.0;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 140),
      opacity: isBusy ? 0.55 : 1,
      child: SizedBox(
        width: outerSize,
        height: outerSize,
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: isRecording ? 94 : 84,
              height: isRecording ? 94 : 84,
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
            ),
            if (isRecording)
              SizedBox(
                width: outerSize,
                height: outerSize,
                child: CircularProgressIndicator(
                  value: progress.clamp(0, 1),
                  strokeWidth: 5,
                  color: Colors.redAccent,
                  backgroundColor: Colors.white.withValues(alpha: 0.28),
                ),
              ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: innerSize,
              height: innerSize,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: isRecording ? BoxShape.rectangle : BoxShape.circle,
                borderRadius: isRecording ? BorderRadius.circular(9) : null,
              ),
            ),
          ],
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
  final _cropController = CropController();
  late File _file;
  Uint8List? _imageBytes;
  bool _isCropping = false;
  bool _isApplyingCrop = false;

  @override
  void initState() {
    super.initState();
    _file = widget.file;
    _loadImageBytes();
  }

  Future<void> _loadImageBytes() async {
    final bytes = await _file.readAsBytes();
    if (!mounted) {
      return;
    }
    setState(() => _imageBytes = bytes);
  }

  void _startCrop() {
    if (_imageBytes == null) {
      return;
    }
    setState(() => _isCropping = true);
  }

  void _cancelCrop() {
    setState(() {
      _isCropping = false;
      _isApplyingCrop = false;
    });
  }

  void _applyCrop() {
    if (_isApplyingCrop) {
      return;
    }
    setState(() => _isApplyingCrop = true);
    _cropController.crop();
  }

  Future<void> _handleCropResult(CropResult result) async {
    switch (result) {
      case CropSuccess(:final croppedImage):
        final file = File(
          '${Directory.systemTemp.path}/bizsooq_crop_${DateTime.now().microsecondsSinceEpoch}.jpg',
        );
        await file.writeAsBytes(croppedImage, flush: true);
        if (!mounted) {
          return;
        }
        setState(() {
          _file = file;
          _imageBytes = croppedImage;
          _isCropping = false;
          _isApplyingCrop = false;
        });
      case CropFailure():
        if (!mounted) {
          return;
        }
        setState(() => _isApplyingCrop = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not crop image')),
        );
    }
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
            child: _imageBytes == null
                ? Image.file(_file, fit: BoxFit.cover)
                : IgnorePointer(
                    ignoring: !_isCropping,
                    child: Crop(
                      image: _imageBytes!,
                      controller: _cropController,
                      onCropped: _handleCropResult,
                      baseColor: Colors.black,
                      maskColor: _isCropping
                          ? Colors.black.withValues(alpha: 0.52)
                          : Colors.transparent,
                      radius: 0,
                      fixCropRect: !_isCropping,
                      interactive: _isCropping,
                      overlayBuilder: _isCropping
                          ? (context, rect) {
                              return CustomPaint(
                painter: _CropGridPainter(),
                              );
                            }
                          : null,
                      withCircleUi: _isCropping,
                    ),
                  ),
          ),
          Positioned(
            top: 14,
            left: 14,
            right: 14,
            child: SafeArea(
              bottom: false,
              child: _isCropping
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _FloatingCircleButton(
                          icon: Icons.close,
                          onTap: _cancelCrop,
                        ),
                        _AcceptButton(onTap: _applyCrop, size: 54),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _FloatingCircleButton(
                          icon: Icons.close,
                          onTap: () => Navigator.pop(context),
                        ),
                        _FloatingCircleButton(
                          icon: Icons.crop,
                          onTap: _startCrop,
                        ),
                      ],
                    ),
            ),
          ),
          if (_isApplyingCrop)
            const Center(child: CircularProgressIndicator(color: Colors.white)),
          Positioned(
            right: 24,
            bottom: 34,
            child: SafeArea(
              child: _isCropping
                  ? const SizedBox.shrink()
                  : _AcceptButton(onTap: _accept, size: 64),
            ),
          ),
        ],
      ),
    );
  }
}

class _CropGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final borderPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..strokeWidth = 1;

    final rect = Offset.zero & size;
    canvas.drawRect(rect, borderPaint);

    final oneThirdWidth = size.width / 3;
    final oneThirdHeight = size.height / 3;
    for (var i = 1; i < 3; i++) {
      final x = oneThirdWidth * i;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      final y = oneThirdHeight * i;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
  RangeValues _trimRange = const RangeValues(0, 0);
  Duration _videoDuration = Duration.zero;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.file);
    _initializeVideo = _controller.initialize().then((_) {
      _videoDuration = _controller.value.duration;
      _trimRange = RangeValues(
        0,
        _videoDuration.inMilliseconds.toDouble(),
      );
      _controller
        ..setLooping(true)
        ..play();
      _controller.addListener(_keepPlaybackInsideTrim);
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_keepPlaybackInsideTrim);
    _controller.dispose();
    super.dispose();
  }

  void _keepPlaybackInsideTrim() {
    if (!_controller.value.isInitialized || _videoDuration == Duration.zero) {
      return;
    }

    final positionMs = _controller.value.position.inMilliseconds.toDouble();
    final startMs = _trimRange.start;
    final endMs = _trimRange.end;
    if (positionMs < startMs || positionMs >= endMs) {
      _controller.seekTo(Duration(milliseconds: startMs.round()));
    }
  }

  Future<void> _accept(BuildContext context) async {
    if (_isProcessing) {
      return;
    }

    final trimChanged =
        _trimRange.start > 250 ||
        (_videoDuration.inMilliseconds - _trimRange.end).abs() > 250;
    if (!trimChanged) {
      Navigator.pop(context, CapturedMedia(file: widget.file, type: 'video'));
      return;
    }

    setState(() => _isProcessing = true);
    final startSeconds = (_trimRange.start / 1000).floor();
    final durationSeconds = ((_trimRange.end - _trimRange.start) / 1000)
        .ceil()
        .clamp(1, 60);
    final info = await VideoCompress.compressVideo(
      widget.file.path,
      quality: VideoQuality.MediumQuality,
      startTime: startSeconds,
      duration: durationSeconds,
      includeAudio: true,
      deleteOrigin: false,
    );
    if (!mounted) {
      return;
    }
    setState(() => _isProcessing = false);
    final editedFile = info?.file ?? widget.file;
    Navigator.pop(context, CapturedMedia(file: editedFile, type: 'video'));
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
                ],
              ),
            ),
          ),
          Positioned(
            left: 14,
            right: 14,
            top: 116,
            child: SafeArea(
              top: false,
              bottom: false,
              child: _VideoTrimBar(
                duration: _videoDuration,
                range: _trimRange,
                onChanged: (value) {
                  setState(() => _trimRange = value);
                  _controller.seekTo(
                    Duration(milliseconds: value.start.round()),
                  );
                },
              ),
            ),
          ),
          Positioned(
            right: 24,
            bottom: 44,
            child: SafeArea(
              child: _isProcessing
                  ? const CircularProgressIndicator(color: Colors.white)
                  : _AcceptButton(onTap: () => _accept(context)),
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoTrimBar extends StatelessWidget {
  const _VideoTrimBar({
    required this.duration,
    required this.range,
    required this.onChanged,
  });

  final Duration duration;
  final RangeValues range;
  final ValueChanged<RangeValues> onChanged;

  @override
  Widget build(BuildContext context) {
    final maxMs = duration.inMilliseconds.toDouble();
    if (maxMs <= 0) {
      return const SizedBox.shrink();
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 5,
          activeTrackColor: Colors.white,
          inactiveTrackColor: Colors.white24,
          thumbColor: Colors.white,
          overlayColor: Colors.white24,
          rangeThumbShape: const RoundRangeSliderThumbShape(
            enabledThumbRadius: 8,
          ),
        ),
        child: RangeSlider(
          min: 0,
          max: maxMs,
          values: RangeValues(
            range.start.clamp(0, maxMs - 1000),
            range.end.clamp(1000, maxMs),
          ),
          onChanged: (value) {
            if (value.end - value.start < 1000) {
              return;
            }
            onChanged(value);
          },
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
