import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:permission_handler/permission_handler.dart' as permissions;
import 'package:video_compress/video_compress.dart';
import 'package:video_player/video_player.dart';

import 'widgets/app_status_bar.dart';
import 'widgets/app_toast.dart';
import 'widgets/item_add/media_picker_sheet.dart';
import 'widgets/video_seek_bar.dart';

class CapturedMedia {
  const CapturedMedia({required this.file, required this.type, this.caption});
  final File file;
  final String type;
  final String? caption;
  bool get isVideo => type == 'video';
}

enum CameraCaptureAction { openGallery }

class GalleryMediaSelection {
  const GalleryMediaSelection({required this.assets, required this.selectedIds});

  final List<AssetEntity> assets;
  final Set<String> selectedIds;
}

class _CameraControllerCache {
  static const _keepAlive = Duration(minutes: 2);
  static CameraController? _controller;
  static CameraDescription? _description;
  static Future<CameraController>? _initializing;
  static Future<void>? _preparingVideo;
  static CameraController? _videoPreparedController;
  static Timer? _releaseTimer;
  static int _activePages = 0;

  static bool _sameCamera(CameraDescription a, CameraDescription b) => a.name == b.name;

  static bool isCurrent(CameraController controller) => identical(_controller, controller);

  static void retain() {
    _activePages++;
    _releaseTimer?.cancel();
  }

  static void release() {
    if (_activePages > 0) _activePages--;
    if (_activePages == 0) scheduleRelease();
  }

  static Future<CameraController> controllerFor(CameraDescription description, {bool forceNew = false}) {
    _releaseTimer?.cancel();
    final current = _controller;
    if (!forceNew &&
        current != null &&
        current.value.isInitialized &&
        _description != null &&
        _sameCamera(_description!, description)) {
      return Future.value(current);
    }
    final pending = _initializing;
    if (!forceNew && pending != null && _description != null && _sameCamera(_description!, description)) {
      return pending;
    }
    _initializing = _create(description);
    return _initializing!;
  }

  static Future<CameraController> _create(CameraDescription description) async {
    try {
      final old = _controller;
      _controller = null;
      _videoPreparedController = null;
      await old?.dispose();
      _description = description;
      final controller = CameraController(
        description,
        ResolutionPreset.high,
        enableAudio: true,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      _controller = controller;
      await controller.initialize();
      return controller;
    } catch (_) {
      _controller = null;
      _description = null;
      rethrow;
    } finally {
      _initializing = null;
    }
  }

  static Future<void> prepareVideo(CameraController controller) {
    if (!controller.value.isInitialized) return Future.value();
    if (identical(_videoPreparedController, controller)) return Future.value();
    return _preparingVideo ??= controller.prepareForVideoRecording().then((_) {
      _videoPreparedController = controller;
    }).catchError((_) {}).whenComplete(() {
      _preparingVideo = null;
    });
  }

  static void scheduleRelease() {
    _releaseTimer?.cancel();
    _releaseTimer = Timer(_keepAlive, releaseNow);
  }

  static Future<void> releaseNow() async {
    if (_activePages > 0) return;
    _releaseTimer?.cancel();
    final pending = _initializing;
    CameraController? current = _controller;
    if (pending != null) {
      try {
        current = await pending;
      } catch (_) {
        current = null;
      }
    }
    if (_activePages > 0) return;
    _controller = null;
    _description = null;
    _initializing = null;
    _preparingVideo = null;
    _videoPreparedController = null;
    await current?.dispose();
  }

  static Future<void> resetCurrent() async {
    _releaseTimer?.cancel();
    final pending = _initializing;
    CameraController? current = _controller;
    if (pending != null) {
      try {
        current = await pending;
      } catch (_) {
        current = null;
      }
    }
    _controller = null;
    _description = null;
    _initializing = null;
    _preparingVideo = null;
    _videoPreparedController = null;
    await current?.dispose();
  }
}

class CameraCapturePage extends StatefulWidget {
  const CameraCapturePage({
    super.key,
    this.selectedCount = 0,
    this.maxCount = 8,
    this.maxSelectionMessage,
    this.embedded = false,
    this.onClose,
    this.onOpenGallery,
    this.onCaptured,
    this.onCapturedAndContinue,
  });

  final int selectedCount;
  final int maxCount;
  final String? maxSelectionMessage;
  final bool embedded;
  final VoidCallback? onClose;
  final VoidCallback? onOpenGallery;
  final ValueChanged<CapturedMedia>? onCaptured;
  final ValueChanged<CapturedMedia>? onCapturedAndContinue;

  static Future<GalleryMediaSelection?> openGalleryPicker(
      BuildContext context, {
        required Set<String> selectedIds,
        required int selectedCount,
        required int maxCount,
        String maxSelectionMessage = 'Only 8 media can be selected',
      }) async {
    GalleryMediaSelection? result;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111614),
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.955,
        child: Column(
          children: [
            Expanded(
              child: MediaPickerSheet(
                selectedIds: selectedIds,
                selectedCount: selectedCount,
                maxCount: maxCount,
                maxSelectionMessage: maxSelectionMessage,
                onAssetsDone: (assets, ids) async {
                  result = GalleryMediaSelection(assets: assets, selectedIds: ids);
                },
              ),
            ),
          ],
        ),
      ),
    );
    return result;
  }

  static Future<List<CameraDescription>>? _cameraListFuture;
  static Future<List<CameraDescription>> preloadCameras() => _cameraListFuture ??= availableCameras();
  static Future<void> prewarmCamera() async {
    try {
      final cam = await permissions.Permission.camera.status;
      final mic = await permissions.Permission.microphone.status;
      if (!cam.isGranted || !mic.isGranted) return;
      final cameras = await preloadCameras();
      if (cameras.isEmpty) return;
      final index = cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
      final controller = await _CameraControllerCache.controllerFor(cameras[index == -1 ? 0 : index]);
      await _CameraControllerCache.prepareVideo(controller);
    } catch (_) {}
  }

  @override
  State<CameraCapturePage> createState() => _CameraCapturePageState();
}

class _CameraCapturePageState extends State<CameraCapturePage> with WidgetsBindingObserver {
  static const _maxDuration = Duration(seconds: 60);
  static const _minVideoDuration = Duration(milliseconds: 800);
  static const _portraitFrameRatio = 9 / 16;
  CameraController? _controller;
  Future<void>? _initFuture;
  List<CameraDescription> _cameras = [];
  int _camIdx = 0;
  bool _isFlash = false, _isRec = false, _isBusy = false;
  Timer? _holdTimer, _tickTimer;
  Duration _elapsed = Duration.zero;
  final ValueNotifier<bool> _recordingListenable = ValueNotifier(false);
  final ValueNotifier<Duration> _elapsedListenable = ValueNotifier(Duration.zero);
  DateTime? _recordStartedAt;
  bool _isResettingZoom = false;
  bool _hasUserZoomed = false;
  double _minZoom = 1.0, _maxZoom = 1.0, _currZoom = 1.0, _startZoom = 1.0;
  double? _startY;
  Offset? _focusPoint;
  int _focusToken = 0;
  Timer? _focusApplyTimer;
  bool _hasPermission = false;
  bool _isCheckingPermission = true;
  File? _previewFile;
  String? _previewType;

  @override
  void initState() {
    super.initState();
    _CameraControllerCache.retain();
    WidgetsBinding.instance.addObserver(this);
    _setImmersive(true);
    _checkPermissionAndSetup();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _setImmersive(false);
    _holdTimer?.cancel();
    _tickTimer?.cancel();
    _focusApplyTimer?.cancel();
    _recordingListenable.dispose();
    _elapsedListenable.dispose();
    unawaited(_resetCameraState(rebuild: false));
    _CameraControllerCache.release();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _holdTimer?.cancel();
      _tickTimer?.cancel();
      unawaited(_resetCameraState(rebuild: false));
      unawaited(_CameraControllerCache.releaseNow());
    }
  }

  void _setImmersive(bool active) {
    if (active) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
      SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
        statusBarColor: Colors.black,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.black,
        systemNavigationBarIconBrightness: Brightness.light,
      ));
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
      SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
        statusBarColor: Colors.black,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
      ));
    }
  }

  Future<void> _checkPermissionAndSetup() async {
    final cam = await permissions.Permission.camera.status;
    final mic = await permissions.Permission.microphone.status;
    if (cam.isGranted && mic.isGranted) {
      setState(() { _hasPermission = true; _isCheckingPermission = false; });
      _initFuture = _setup();
    } else {
      setState(() { _hasPermission = false; _isCheckingPermission = false; });
    }
  }

  Future<void> _requestPermission() async {
    final status = await [permissions.Permission.camera, permissions.Permission.microphone].request();
    if (status[permissions.Permission.camera]?.isGranted == true && status[permissions.Permission.microphone]?.isGranted == true) {
      setState(() { _hasPermission = true; });
      _initFuture = _setup();
    } else {
      permissions.openAppSettings();
    }
  }

  bool _hasReachedMediaLimit() {
    if (widget.selectedCount < widget.maxCount) return false;
    final message = widget.maxSelectionMessage;
    if (message != null && message.isNotEmpty) {
      AppToast.show(context, message);
    }
    return true;
  }

  Future<void> _setup() async {
    _cameras = await CameraCapturePage.preloadCameras();
    if (_cameras.isEmpty) return;
    _camIdx = _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
    if (_camIdx == -1) _camIdx = 0;
    await _initCam(_cameras[_camIdx]);
  }

  Future<void> _initCam(CameraDescription desc) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final c = await _CameraControllerCache.controllerFor(desc, forceNew: attempt == 1);
        if (!mounted) return;
        if (!_CameraControllerCache.isCurrent(c) || !c.value.isInitialized) {
          if (attempt == 0) continue;
          return;
        }
        _controller = c;
        await c.lockCaptureOrientation(DeviceOrientation.portraitUp);
        unawaited(_prepareFocusModes(c));
        _minZoom = await c.getMinZoomLevel();
        _maxZoom = await c.getMaxZoomLevel();
        _currZoom = _minZoom;
        await _resetZoom(rebuild: false);
        unawaited(_CameraControllerCache.prepareVideo(c));
        setState(() {});
        return;
      } catch (_) {
        if (attempt == 1) rethrow;
      }
    }
  }

  Future<void> _toggleFlash() async {
    if (_controller == null || !_controller!.value.isInitialized || _isRec || _isBusy) return;
    try {
      final next = !_isFlash;
      await _controller!.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      setState(() => _isFlash = next);
    } catch (_) {}
  }

  Future<void> _resetFlash({bool rebuild = true}) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    _isFlash = false;
    try {
      await controller.setFlashMode(FlashMode.off);
    } catch (_) {}
    if (rebuild && mounted) setState(() {});
  }

  void _onPressStart(TapDownDetails d) {
    if (_isBusy) return;
    if (_hasReachedMediaLimit()) return;
    _startY = d.globalPosition.dy;
    _startZoom = _currZoom;
    _holdTimer = Timer(const Duration(milliseconds: 400), _startRec);
  }

  void _onPressEnd() {
    if (_holdTimer?.isActive ?? false) {
      _holdTimer?.cancel();
      _takePhoto();
    } else if (_isRec) {
      _stopRec();
    }
    _startY = null;
  }

  void _onMove(PointerMoveEvent e) {
    if (!_isRec || _startY == null) return;
    final dist = _startY! - e.position.dy;
    final delta = (dist / 160).clamp(0.0, 1.0) * (_maxZoom - _minZoom);
    final nextZoom = (_startZoom + delta).clamp(_minZoom, _maxZoom);
    _setZoom(nextZoom, updateUI: (nextZoom - _currZoom).abs() >= 0.05);
  }

  void _setZoom(double zoom, {bool updateUI = true}) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (_previewFile != null || _isBusy || _isResettingZoom) return;
    if ((zoom - _currZoom).abs() < 0.01) return;
    _currZoom = zoom;
    if (zoom > _minZoom + 0.01) _hasUserZoomed = true;
    unawaited(controller.setZoomLevel(zoom));
    if (updateUI && mounted) setState(() {});
  }

  Future<void> _resetZoom({bool rebuild = true}) async {
    // Cancel any queued zoom immediately — don't wait for in-flight ops.
    await _forceResetZoom(rebuild: rebuild);
  }

  Future<void> _forceResetZoom({bool rebuild = true}) async {
    _isResettingZoom = true;
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      _isResettingZoom = false;
      return;
    }
    final zoom = _minZoom;
    _currZoom = zoom;
    _startZoom = zoom;
    try {
      await controller.setZoomLevel(zoom);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await controller.setZoomLevel(zoom);
    } catch (_) {
    } finally {
      _isResettingZoom = false;
    }
    if (rebuild && mounted) setState(() {});
  }

  Future<void> _resetCameraState({bool rebuild = true}) async {
    await _resetFlash(rebuild: false);
    await _resetZoom(rebuild: false);
    if (rebuild && mounted) setState(() {});
  }

  Future<void> _resetCachedControllerAfterZoom({bool reopen = false}) async {
    if (!_hasUserZoomed) return;
    _hasUserZoomed = false;
    _controller = null;
    await _CameraControllerCache.resetCurrent();
    if (reopen && mounted) {
      _initFuture = _setup();
    }
  }

  Future<void> _closeCamera() async {
    await _resetCameraState(rebuild: false);
    await _resetCachedControllerAfterZoom();
    if (!mounted) return;
    if (widget.embedded) {
      widget.onClose?.call();
      return;
    }
    Navigator.pop(context);
  }

  void _openGallery() {
    if (widget.embedded) {
      widget.onOpenGallery?.call();
      return;
    }
    Navigator.pop(context, CameraCaptureAction.openGallery);
  }

  Future<void> _finishCaptured(CapturedMedia media) async {
    await _resetCameraState(rebuild: false);
    await _resetCachedControllerAfterZoom();
    if (!mounted) return;
    if (widget.embedded) {
      widget.onCaptured?.call(media);
      return;
    }
    Navigator.pop(context, media);
  }

  void _finishCapturedAndContinue(CapturedMedia media) {
    widget.onCapturedAndContinue?.call(media);
    if (!mounted) return;
    setState(() {
      _previewFile = null;
      _previewType = null;
    });
  }

  void _showPreview(File file, String type) {
    setState(() {
      _previewFile = file;
      _previewType = type;
      _isBusy = false;
    });
  }

  Future<void> _closePreview() async {
    await _resetCameraState(rebuild: false);
    await _resetCachedControllerAfterZoom(reopen: true);
    if (!mounted) return;
    setState(() {
      _previewFile = null;
      _previewType = null;
    });
  }

  Future<void> _onTapFocus(TapDownDetails d) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _isRec) return;
    final box = context.findRenderObject() as RenderBox;
    final point = box.globalToLocal(d.globalPosition);
    final size = box.size;
    final norm = Offset(
      (point.dx / size.width).clamp(0.0, 1.0).toDouble(),
      (point.dy / size.height).clamp(0.0, 1.0).toDouble(),
    );
    final token = ++_focusToken;
    setState(() => _focusPoint = point);
    _focusApplyTimer?.cancel();
    _focusApplyTimer = Timer(const Duration(milliseconds: 35), () {
      if (mounted && token == _focusToken) {
        unawaited(_applyTapFocus(controller, norm, token));
      }
    });
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted && token == _focusToken) setState(() => _focusPoint = null);
    });
  }

  Future<void> _prepareFocusModes(CameraController controller) async {
    try {
      await controller.setFocusMode(FocusMode.auto);
    } catch (_) {}
    try {
      await controller.setExposureMode(ExposureMode.auto);
    } catch (_) {}
  }

  Future<void> _applyTapFocus(
    CameraController controller,
    Offset point,
    int token,
  ) async {
    if (!_isActiveFocusRequest(controller, token)) return;
    try {
      await controller.setFocusPoint(point);
    } catch (_) {}
    if (!_isActiveFocusRequest(controller, token)) return;
    await Future<void>.delayed(const Duration(milliseconds: 45));
    if (!_isActiveFocusRequest(controller, token)) return;
    try {
      await controller.setExposurePoint(point);
    } catch (_) {}
  }

  bool _isActiveFocusRequest(CameraController controller, int token) {
    return mounted &&
        token == _focusToken &&
        identical(controller, _controller) &&
        controller.value.isInitialized &&
        !_isRec;
  }

  Future<void> _takePhoto() async {
    if (_controller == null || !_controller!.value.isInitialized || _isBusy) return;
    setState(() => _isBusy = true);
    HapticFeedback.lightImpact();
    try {
      final f = await _controller!.takePicture();
      if (!mounted) return;
      _showPreview(File(f.path), 'image');
      unawaited(_resetCameraState(rebuild: false));
    } catch (_) {} finally { if (mounted) setState(() => _isBusy = false); }
  }

  Future<void> _startRec() async {
    if (_controller == null || !_controller!.value.isInitialized || _isRec || _isBusy) return;
    try {
      if (_controller!.value.isRecordingVideo) return;
      await _CameraControllerCache.prepareVideo(_controller!);
      await _controller!.startVideoRecording();
      HapticFeedback.heavyImpact();
      _recordStartedAt = DateTime.now();
      _isRec = true;
      _elapsed = Duration.zero;
      _recordingListenable.value = true;
      _elapsedListenable.value = Duration.zero;
      _tickTimer = Timer.periodic(const Duration(milliseconds: 250), (t) {
        if (!mounted || !_isRec) { t.cancel(); return; }
        _elapsed += const Duration(milliseconds: 250);
        _elapsedListenable.value = _elapsed;
        if (_elapsed >= _maxDuration) _stopRec();
      });
    } catch (e) { debugPrint('Error starting video recording: $e'); }
  }

  Future<void> _stopRec() async {
    if (!_isRec || _isBusy || _controller == null) return;
    _tickTimer?.cancel();
    final recordedFor = _recordStartedAt == null
        ? _elapsed
        : DateTime.now().difference(_recordStartedAt!);
    _recordStartedAt = null;
    _isRec = false;
    _recordingListenable.value = false;
    setState(() { _isBusy = true; });
    try {
      if (!_controller!.value.isRecordingVideo) { setState(() => _isBusy = false); return; }
      final f = await _controller!.stopVideoRecording();
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      final file = File(f.path);
      if (await file.exists()) {
        if (recordedFor < _minVideoDuration) {
          try { await file.delete(); } catch (_) {}
          if (mounted) AppToast.show(context, 'Hold longer to record video');
          return;
        }
        if (!mounted) return;
        _showPreview(file, 'video');
        unawaited(_resetCameraState(rebuild: false));
      }
    } catch (e) { debugPrint('Error stopping video recording: $e'); }
    finally { if (mounted) setState(() => _isBusy = false); }
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingPermission) return _wrapCameraPage(_buildCameraShell(const SizedBox.shrink()));
    if (!_hasPermission) return _buildPermissionPrompt();
    return _wrapCameraPage(
      FutureBuilder(
        future: _initFuture,
        builder: (ctx, snap) {
          final controller = _controller;
          final isReady = controller != null && controller.value.isInitialized;
          final previewFile = _previewFile;
          return _buildCameraShell(
            previewFile != null
                ? (_previewType == 'video'
                ? _InlineVideoPreview(
              file: previewFile,
              onConfirm: _finishCaptured,
              onClose: _closePreview,
            )
                : _InlineImagePreview(
              file: previewFile,
              onConfirm: _finishCaptured,
              onConfirmAndContinue: widget.embedded ? _finishCapturedAndContinue : null,
              onClose: _closePreview,
            ))
                : isReady
                ? GestureDetector(
              onTapDown: _onTapFocus,
              onScaleStart: (_) => _startZoom = _currZoom,
              onScaleUpdate: (d) => _setZoom((_startZoom * d.scale).clamp(_minZoom, _maxZoom), updateUI: false),
              child: RepaintBoundary(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: AspectRatio(
                    aspectRatio: _portraitFrameRatio,
                    child: RepaintBoundary(
                      child: ClipRect(child: CameraPreview(controller)),
                    ),
                  ),
                ),
              ),
            )
                : Center(
              child: snap.connectionState == ConnectionState.done
                  ? const Text('Camera error', style: TextStyle(color: Colors.white))
                  : const SizedBox.shrink(),
            ),
          );
        },
      ),
    );
  }

  Widget _wrapCameraPage(Widget child) {
    if (widget.embedded) return child;
    return Scaffold(backgroundColor: Colors.black, body: child);
  }

  Widget _buildCameraShell(Widget preview) => ColoredBox(
    color: Colors.black,
    child: Column(
      children: [
        if (!widget.embedded) const AppStatusBar(),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(child: preview),
              if (_previewFile == null) ...[
                if (_focusPoint != null) Positioned(left: _focusPoint!.dx - 35, top: _focusPoint!.dy - 35, child: _FocusRing()),
                _buildTopBar(),
                _buildBottomControls(),
              ],
            ],
          ),
        ),
      ],
    ),
  );

  Widget _buildPermissionPrompt() => _wrapCameraPage(Center(child: Padding(
    padding: const EdgeInsets.all(32),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.camera_alt, color: Colors.white, size: 64),
      const SizedBox(height: 24),
      const Text('Camera and Microphone access needed.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 16)),
      const SizedBox(height: 32),
      ElevatedButton(
        onPressed: _requestPermission,
        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF25D366), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
        child: const Text('Grant Permission', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    ]),
  )));

  Widget _buildTopBar() => ValueListenableBuilder<bool>(
    valueListenable: _recordingListenable,
    builder: (context, isRec, _) => Stack(children: [
      if (isRec)
        Positioned(
          top: 10,
          left: 0,
          right: 0,
          child: Center(child: _buildRecTimer()),
        )
      else
        Positioned(
          top: 0, right: 0,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: _CircleBtn(
              icon: _isFlash ? Icons.flash_on : Icons.flash_off,
              onTap: _toggleFlash,
            ),
          ),
        ),
    ]),
  );

  Widget _buildRecTimer() => ValueListenableBuilder<Duration>(
    valueListenable: _elapsedListenable,
    builder: (context, elapsed, _) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: Colors.red,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(_formatDur(elapsed), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ]),
    ),
  );

  Widget _buildBottomControls() => Positioned(
    bottom: 52, left: 0, right: 0,
    child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _CircleBtn(icon: Icons.photo_library, onTap: _openGallery),
                ValueListenableBuilder<bool>(
                  valueListenable: _recordingListenable,
                  builder: (context, isRec, _) =>
                      ValueListenableBuilder<Duration>(
                    valueListenable: _elapsedListenable,
                    builder: (context, elapsed, _) => _CaptureBtn(
                      isRec: isRec,
                      progress:
                          elapsed.inMilliseconds / _maxDuration.inMilliseconds,
                      onStart: _onPressStart,
                      onEnd: _onPressEnd,
                      onMove: _onMove,
                    ),
                  ),
                ),
                _CircleBtn(icon: Icons.close, onTap: _closeCamera),
              ],
            ),
          ),
          const SizedBox(height: 6),
        ])),
  );

  String _formatDur(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
}

class _CaptureBtn extends StatelessWidget {
  final bool isRec;
  final double progress;
  final ValueChanged<TapDownDetails> onStart;
  final VoidCallback onEnd;
  final ValueChanged<PointerMoveEvent> onMove;
  const _CaptureBtn({
    required this.isRec,
    required this.progress,
    required this.onStart,
    required this.onEnd,
    required this.onMove,
  });

  @override
  Widget build(BuildContext context) => Listener(
    onPointerMove: onMove, onPointerUp: (_) => onEnd(), onPointerCancel: (_) => onEnd(),
    child: GestureDetector(
      onTapDown: onStart,
      child: Container(
        width: 84, height: 84,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4)),
        child: Stack(alignment: Alignment.center, children: [
          if (isRec) SizedBox(width: 74, height: 74, child: CircularProgressIndicator(value: progress, color: Colors.red, strokeWidth: 4)),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            transitionBuilder: (child, animation) => ScaleTransition(
              scale: animation,
              child: child,
            ),
            child: Container(
              key: ValueKey(isRec),
              width: isRec ? 30 : 64,
              height: isRec ? 30 : 64,
              decoration: isRec
                  ? BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(4),
              )
                  : const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ]),
      ),
    ),
  );
}

class _CircleBtn extends StatelessWidget {
  final IconData icon; final VoidCallback onTap;
  const _CircleBtn({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: CircleAvatar(backgroundColor: Colors.black38, radius: 24, child: Icon(icon, color: Colors.white, size: 28)),
  );
}

class _FocusRing extends StatelessWidget {
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 1.0, end: 0.0), duration: const Duration(milliseconds: 300),
    builder: (ctx, val, child) => Container(
      width: 70, height: 70,
      decoration: BoxDecoration(border: Border.all(color: Colors.yellow.withValues(alpha: val), width: 2), shape: BoxShape.circle),
    ),
  );
}

class _InlineImagePreview extends StatelessWidget {
  const _InlineImagePreview({
    required this.file,
    required this.onConfirm,
    this.onConfirmAndContinue,
    required this.onClose,
  });

  final File file;
  final ValueChanged<CapturedMedia> onConfirm;
  final ValueChanged<CapturedMedia>? onConfirmAndContinue;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(
        child: Align(
          alignment: Alignment.topCenter,
          child: AspectRatio(
            aspectRatio: _CameraCapturePageState._portraitFrameRatio,
            child: Image.file(file, fit: BoxFit.contain),
          ),
        ),
      ),
      _PreviewBottomControls(
        onConfirm: () => onConfirm(CapturedMedia(file: file, type: 'image')),
        onClose: onClose,
        leading: onConfirmAndContinue == null
            ? null
            : _CameraContinueButton(
                onTap: () => onConfirmAndContinue!(
                  CapturedMedia(file: file, type: 'image'),
                ),
              ),
      ),
    ],
  );
}

class _InlineVideoPreview extends StatefulWidget {
  const _InlineVideoPreview({
    required this.file,
    required this.onConfirm,
    required this.onClose,
  });

  final File file;
  final ValueChanged<CapturedMedia> onConfirm;
  final VoidCallback onClose;

  @override
  State<_InlineVideoPreview> createState() => _InlineVideoPreviewState();
}

class _InlineVideoPreviewState extends State<_InlineVideoPreview> {
  late VideoPlayerController _controller;
  Timer? _overlayTimer;
  bool _isInit = false, _isMuted = false, _showPlaybackIcon = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.file);
    _controller.initialize().then((_) {
      if (!mounted) return;
      setState(() {
        _isInit = true;
      });
      _controller
        ..setLooping(true)
        ..play();
    }).catchError((e) {
      if (mounted) setState(() => _err = e.toString());
    });
  }

  @override
  void dispose() {
    _overlayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _togglePlayback() {
    if (!_isInit) return;
    _overlayTimer?.cancel();
    if (_controller.value.isPlaying) {
      _controller.pause();
      setState(() => _showPlaybackIcon = true);
      return;
    }
    _controller.play();
    setState(() => _showPlaybackIcon = true);
    _overlayTimer = Timer(const Duration(seconds: 1), () {
      if (mounted && _controller.value.isPlaying) {
        setState(() => _showPlaybackIcon = false);
      }
    });
  }

  Future<void> _send() async {
    File finalFile = widget.file;

    if (_isMuted) {
      _overlayTimer?.cancel();
      await _controller.pause();
      await _controller.setVolume(0);
      setState(() => _isInit = false);
      final info = await VideoCompress.compressVideo(
        widget.file.path,
        quality: VideoQuality.MediumQuality,
        includeAudio: false,
      );
      if (info?.file != null) finalFile = info!.file!;
    }

    widget.onConfirm(CapturedMedia(file: finalFile, type: 'video'));
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      if (_isInit)
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _togglePlayback,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Align(
                alignment: Alignment.topCenter,
                child: AspectRatio(
                  aspectRatio: _CameraCapturePageState._portraitFrameRatio,
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: _controller.value.aspectRatio,
                      child: VideoPlayer(_controller),
                    ),
                  ),
                ),
              ),
              if (_showPlaybackIcon || !_controller.value.isPlaying)
                AnimatedOpacity(
                  opacity: 1,
                  duration: const Duration(milliseconds: 120),
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      color: Colors.black45,
                      shape: BoxShape.circle,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Icon(
                        _controller.value.isPlaying ? Icons.play_arrow : Icons.pause,
                        color: Colors.white,
                        size: 46,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      if (_isInit)
        Positioned(
          top: 14,
          left: 18,
          right: 18,
          child: AppVideoSeekBar(controller: _controller),
        )
      else if (_err != null)
        Center(child: Text(_err!, style: const TextStyle(color: Colors.white)))
      else
        const Center(child: CircularProgressIndicator(color: Colors.white)),
      _PreviewBottomControls(
        onConfirm: _send,
        onClose: widget.onClose,
        leading: _CircleBtn(
          icon: _isMuted ? Icons.volume_off : Icons.volume_up,
          onTap: () {
            setState(() {
              _isMuted = !_isMuted;
              _controller.setVolume(_isMuted ? 0 : 1);
            });
          },
        ),
      ),
    ],
  );
}

class _PreviewBottomControls extends StatelessWidget {
  const _PreviewBottomControls({
    required this.onConfirm,
    required this.onClose,
    this.leading,
  });

  final VoidCallback onConfirm;
  final VoidCallback onClose;
  final Widget? leading;

  @override
  Widget build(BuildContext context) => Positioned(
    bottom: 52,
    left: 0,
    right: 0,
    child: SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                leading ?? const SizedBox(width: 48, height: 48),
                GestureDetector(
                  onTap: onConfirm,
                  child: Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: Color(0xFF25D366),
                      size: 48,
                      weight: 900,
                    ),
                  ),
                ),
                _CircleBtn(icon: Icons.close, onTap: onClose),
              ],
            ),
          ),
          const SizedBox(height: 6),
        ],
      ),
    ),
  );
}

class _CameraContinueButton extends StatelessWidget {
  const _CameraContinueButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: const CircleAvatar(
        backgroundColor: Colors.black38,
        radius: 24,
        child: Icon(Icons.add_a_photo, color: Colors.white, size: 26),
      ),
    );
  }
}
