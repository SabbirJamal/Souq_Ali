import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart' as permissions;
import 'package:photo_manager/photo_manager.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_player/video_player.dart';

class CapturedMedia {
  const CapturedMedia({required this.file, required this.type, this.caption});
  final File file;
  final String type;
  final String? caption;
  bool get isVideo => type == 'video';
}

enum CameraCaptureAction { openGallery }

class _CameraControllerCache {
  static const _keepAlive = Duration(minutes: 2);
  static CameraController? _controller;
  static CameraDescription? _description;
  static Future<CameraController>? _initializing;
  static Future<void>? _preparingVideo;
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
    return _preparingVideo ??= controller.prepareForVideoRecording().catchError((_) {}).whenComplete(() {
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
    await current?.dispose();
  }
}

class CameraCapturePage extends StatefulWidget {
  const CameraCapturePage({super.key});
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
      await _CameraControllerCache.controllerFor(cameras[index == -1 ? 0 : index]);
    } catch (_) {}
  }

  @override
  State<CameraCapturePage> createState() => _CameraCapturePageState();
}

class _CameraCapturePageState extends State<CameraCapturePage> with WidgetsBindingObserver {
  static const _maxDuration = Duration(seconds: 60);
  CameraController? _controller;
  Future<void>? _initFuture;
  List<CameraDescription> _cameras = [];
  int _camIdx = 0;
  bool _isFlash = false, _isRec = false, _isBusy = false;
  Timer? _holdTimer, _tickTimer;
  Duration _elapsed = Duration.zero;
  double _minZoom = 1.0, _maxZoom = 1.0, _currZoom = 1.0, _startZoom = 1.0;
  double? _startY;
  Offset? _focusPoint;
  List<AssetEntity> _recent = [];
  int _loadToken = 0;
  bool _hasPermission = false;
  bool _isCheckingPermission = true;

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
    _holdTimer?.cancel(); _tickTimer?.cancel();
    _CameraControllerCache.release();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _holdTimer?.cancel();
      _tickTimer?.cancel();
      unawaited(_CameraControllerCache.releaseNow());
    }
  }

  void _setImmersive(bool active) {
    if (active) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
      SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(statusBarColor: Colors.black));
    }
  }

  Future<void> _checkPermissionAndSetup() async {
    final cam = await permissions.Permission.camera.status;
    final mic = await permissions.Permission.microphone.status;
    if (cam.isGranted && mic.isGranted) {
      setState(() { _hasPermission = true; _isCheckingPermission = false; });
      _initFuture = _setup();
      _loadRecent();
    } else {
      setState(() { _hasPermission = false; _isCheckingPermission = false; });
    }
  }

  Future<void> _requestPermission() async {
    final status = await [permissions.Permission.camera, permissions.Permission.microphone].request();
    if (status[permissions.Permission.camera]?.isGranted == true && status[permissions.Permission.microphone]?.isGranted == true) {
      setState(() { _hasPermission = true; });
      _initFuture = _setup();
      _loadRecent();
    } else {
      permissions.openAppSettings();
    }
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
        _minZoom = await c.getMinZoomLevel();
        _maxZoom = await c.getMaxZoomLevel();
        _currZoom = _minZoom;
        await c.setZoomLevel(_currZoom);
        setState(() {});
        unawaited(_CameraControllerCache.prepareVideo(c));
        return;
      } catch (_) {
        if (attempt == 1) rethrow;
      }
    }
  }

  Future<void> _flip() async {
    if (_cameras.length < 2 || _isRec || _isBusy) return;
    HapticFeedback.mediumImpact();
    _camIdx = (_camIdx + 1) % _cameras.length;
    setState(() {
      _controller = null;
      _initFuture = _initCam(_cameras[_camIdx]);
    });
  }

  Future<void> _toggleFlash() async {
    if (_controller == null || !_controller!.value.isInitialized || _isRec || _isBusy) return;
    try {
      final next = !_isFlash;
      await _controller!.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      setState(() => _isFlash = next);
    } catch (_) {}
  }

  Future<void> _loadRecent() async {
    final token = ++_loadToken;
    try {
      final res = await PhotoManager.requestPermissionExtend();
      if (!res.hasAccess) return;
      final paths = await PhotoManager.getAssetPathList(type: RequestType.common, onlyAll: true);
      if (paths.isEmpty) return;
      final assets = await paths.first.getAssetListPaged(page: 0, size: 10);
      if (mounted && token == _loadToken) setState(() => _recent = assets);
    } catch (_) {}
  }

  void _onPressStart(TapDownDetails d) {
    if (_isBusy) return;
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
    _setZoom((_startZoom + delta).clamp(_minZoom, _maxZoom));
  }

  void _setZoom(double zoom) {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if ((zoom - _currZoom).abs() < 0.01) return;
    _currZoom = zoom;
    _controller!.setZoomLevel(zoom);
    setState(() {});
  }

  Future<void> _onTapFocus(TapDownDetails d) async {
    if (_controller == null || !_controller!.value.isInitialized || _isRec) return;
    final box = context.findRenderObject() as RenderBox;
    final point = box.globalToLocal(d.globalPosition);
    final size = box.size;
    final norm = Offset(point.dx / size.width, point.dy / size.height);
    try {
      await _controller!.setFocusPoint(norm);
      await _controller!.setExposurePoint(norm);
      setState(() => _focusPoint = point);
      Future.delayed(const Duration(seconds: 1), () { if (mounted) setState(() => _focusPoint = null); });
    } catch (_) {}
  }

  Future<void> _takePhoto() async {
    if (_controller == null || !_controller!.value.isInitialized || _isBusy) return;
    setState(() => _isBusy = true);
    HapticFeedback.lightImpact();
    try {
      final f = await _controller!.takePicture();
      if (!mounted) return;
      final res = await Navigator.push<CapturedMedia>(context, MaterialPageRoute(builder: (_) => _ImagePreviewPage(file: File(f.path))));
      if (res != null && mounted) Navigator.pop(context, res);
    } catch (_) {} finally { if (mounted) setState(() => _isBusy = false); }
  }

  Future<void> _startRec() async {
    if (_controller == null || !_controller!.value.isInitialized || _isRec || _isBusy) return;
    try {
      if (_controller!.value.isRecordingVideo) return;
      await _CameraControllerCache.prepareVideo(_controller!);
      await _controller!.startVideoRecording();
      HapticFeedback.heavyImpact();
      if (mounted) setState(() { _isRec = true; _elapsed = Duration.zero; });
      _tickTimer = Timer.periodic(const Duration(milliseconds: 100), (t) {
        if (!mounted || !_isRec) { t.cancel(); return; }
        setState(() => _elapsed += const Duration(milliseconds: 100));
        if (_elapsed >= _maxDuration) _stopRec();
      });
    } catch (e) { debugPrint('Error starting video recording: $e'); }
  }

  Future<void> _stopRec() async {
    if (!_isRec || _isBusy || _controller == null) return;
    _tickTimer?.cancel();
    setState(() { _isRec = false; _isBusy = true; });
    try {
      if (!_controller!.value.isRecordingVideo) { setState(() => _isBusy = false); return; }
      final f = await _controller!.stopVideoRecording();
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      await Future.delayed(const Duration(milliseconds: 300));
      final file = File(f.path);
      if (await file.exists()) {
        if (!mounted) return;
        final res = await Navigator.push<CapturedMedia>(context, MaterialPageRoute(builder: (_) => _VideoPreviewPage(file: file)));
        if (res != null && mounted) Navigator.pop(context, res);
      }
    } catch (e) { debugPrint('Error stopping video recording: $e'); }
    finally { if (mounted) setState(() => _isBusy = false); }
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingPermission) return _buildCameraShell(const CircularProgressIndicator(color: Colors.white));
    if (!_hasPermission) return _buildPermissionPrompt();
    return Scaffold(
      backgroundColor: Colors.black,
      body: FutureBuilder(
        future: _initFuture,
        builder: (ctx, snap) {
          final controller = _controller;
          final isReady = controller != null && controller.value.isInitialized;
          return _buildCameraShell(
            isReady
                ? GestureDetector(
                    onTapDown: _onTapFocus,
                    onDoubleTap: _flip,
                    onScaleUpdate: (d) => _setZoom((_currZoom * d.scale).clamp(_minZoom, _maxZoom)),
                    child: RepaintBoundary(child: Center(child: CameraPreview(controller))),
                  )
                : Center(
                    child: snap.connectionState == ConnectionState.done
                        ? const Text('Camera error', style: TextStyle(color: Colors.white))
                        : const CircularProgressIndicator(color: Colors.white),
                  ),
          );
        },
      ),
    );
  }

  Widget _buildCameraShell(Widget preview) => Scaffold(
    backgroundColor: Colors.black,
    body: Stack(
      children: [
        Positioned.fill(child: preview),
        if (_focusPoint != null) Positioned(left: _focusPoint!.dx - 35, top: _focusPoint!.dy - 35, child: _FocusRing()),
        _buildTopBar(),
        _buildBottomControls(),
      ],
    ),
  );

  Widget _buildPermissionPrompt() => Scaffold(
    backgroundColor: Colors.black,
    body: Center(child: Padding(
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
    )),
  );

  Widget _buildTopBar() => Positioned(
    top: 0, left: 0, right: 0,
    child: SafeArea(child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        _CircleBtn(icon: Icons.close, onTap: () => Navigator.pop(context)),
        if (_isRec) _buildRecTimer() else _CircleBtn(icon: _isFlash ? Icons.flash_on : Icons.flash_off, onTap: _toggleFlash),
      ]),
    )),
  );

  Widget _buildRecTimer() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)),
      const SizedBox(width: 8),
      Text(_formatDur(_elapsed), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
    ]),
  );

  Widget _buildBottomControls() => Positioned(
    bottom: 0, left: 0, right: 0,
    child: SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      if (!_isRec && _recent.isNotEmpty) GestureDetector(
        onVerticalDragEnd: (d) { if (d.primaryVelocity != null && d.primaryVelocity! < -300) Navigator.pop(context, CameraCaptureAction.openGallery); },
        child: _RecentStrip(assets: _recent, onSelect: (a) async {
          final f = await a.fileWithSubtype ?? await a.file;
          if (f != null && mounted) Navigator.pop(context, CapturedMedia(file: f, type: a.type == AssetType.video ? 'video' : 'image'));
        }),
      ),
      const SizedBox(height: 16),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20), child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _CircleBtn(icon: Icons.photo_library, onTap: () => Navigator.pop(context, CameraCaptureAction.openGallery)),
          _CaptureBtn(isRec: _isRec, progress: _elapsed.inMilliseconds / _maxDuration.inMilliseconds, onStart: _onPressStart, onEnd: _onPressEnd, onMove: _onMove),
          _CircleBtn(icon: Icons.flip_camera_android, onTap: _flip),
        ],
      )),
      if (!_isRec) const Text('Hold for video, tap for photo', style: TextStyle(color: Colors.white70, fontSize: 12)),
      const SizedBox(height: 10),
    ])),
  );

  String _formatDur(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
}

class _CaptureBtn extends StatelessWidget {
  final bool isRec; final double progress;
  final ValueChanged<TapDownDetails> onStart; final VoidCallback onEnd; final ValueChanged<PointerMoveEvent> onMove;
  const _CaptureBtn({required this.isRec, required this.progress, required this.onStart, required this.onEnd, required this.onMove});

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
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: isRec ? 30 : 64, height: isRec ? 30 : 64,
            decoration: BoxDecoration(color: isRec ? Colors.red : Colors.white, shape: isRec ? BoxShape.rectangle : BoxShape.circle, borderRadius: isRec ? BorderRadius.circular(4) : null),
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

class _RecentStrip extends StatelessWidget {
  final List<AssetEntity> assets; final ValueChanged<AssetEntity> onSelect;
  const _RecentStrip({required this.assets, required this.onSelect});
  Widget _tile(AssetEntity asset) {
    return FutureBuilder<Uint8List?>(
      future: asset.thumbnailDataWithSize(const ThumbnailSize.square(200)),
      builder: (context, snapshot) {
        if (snapshot.data == null) return Container(width: 70, height: 70, color: Colors.white10);
        return Image.memory(snapshot.data!, width: 70, height: 70, fit: BoxFit.cover);
      },
    );
  }
  @override
  Widget build(BuildContext context) => Column(children: [
    const Icon(Icons.keyboard_arrow_up, color: Colors.white70, size: 20),
    const SizedBox(height: 4),
    SizedBox(
      height: 70,
      child: ListView.builder(
        scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: assets.length,
        itemBuilder: (ctx, i) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(onTap: () => onSelect(assets[i]), child: ClipRRect(borderRadius: BorderRadius.circular(8), child: _tile(assets[i]))),
        ),
      ),
    ),
  ]);
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

class _ImagePreviewPage extends StatefulWidget {
  final File file;
  const _ImagePreviewPage({required this.file});
  @override
  State<_ImagePreviewPage> createState() => _ImagePreviewPageState();
}

class _ImagePreviewPageState extends State<_ImagePreviewPage> {
  final _crop = CropController();
  final _caption = TextEditingController();
  bool _isCropping = false;
  late File _currFile;

  @override
  void initState() { super.initState(); _currFile = widget.file; }
  @override
  void dispose() { _caption.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        Positioned.fill(child: _isCropping 
          ? Crop(image: _currFile.readAsBytesSync(), controller: _crop, onCropped: (res) async {
              if (res is CropSuccess) {
                final f = File('${(await getTemporaryDirectory()).path}/crop_${DateTime.now().millisecondsSinceEpoch}.jpg');
                await f.writeAsBytes(res.croppedImage);
                setState(() { _currFile = f; _isCropping = false; });
              }
            })
          : Image.file(_currFile, fit: BoxFit.contain)),
        Positioned(top: 10, left: 10, child: SafeArea(child: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)))),
        if (!_isCropping) Positioned(top: 10, right: 10, child: SafeArea(child: IconButton(icon: const Icon(Icons.crop, color: Colors.white), onPressed: () => setState(() => _isCropping = true)))),
        if (!_isCropping) Positioned(
          bottom: 20, left: 16, right: 84,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(24)),
            child: TextField(controller: _caption, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: 'Add a caption...', hintStyle: TextStyle(color: Colors.white70), border: InputBorder.none, isDense: true)),
          ),
        ),
        Positioned(bottom: 20, right: 20, child: FloatingActionButton(backgroundColor: const Color(0xFF25D366), onPressed: () {
          if (_isCropping) _crop.crop(); 
          else Navigator.pop(context, CapturedMedia(file: _currFile, type: 'image', caption: _caption.text));
        }, child: Icon(_isCropping ? Icons.check : Icons.send))),
      ]),
    );
  }
}

class _VideoPreviewPage extends StatefulWidget {
  final File file;
  const _VideoPreviewPage({required this.file});
  @override
  State<_VideoPreviewPage> createState() => _VideoPreviewPageState();
}

class _VideoPreviewPageState extends State<_VideoPreviewPage> {
  late VideoPlayerController _c;
  final _caption = TextEditingController();
  bool _isInit = false, _isMuted = false;
  String? _err;
  RangeValues _trim = const RangeValues(0, 1);
  Duration _dur = Duration.zero;

  @override
  void initState() {
    super.initState();
    _c = VideoPlayerController.file(widget.file);
    _c.initialize().then((_) {
      if (mounted) {
        setState(() {
          _isInit = true;
          _dur = _c.value.duration;
          _trim = RangeValues(0, _dur.inMilliseconds.toDouble());
          _c.play();
          _c.setLooping(true);
        });
        _c.addListener(_checkTrim);
      }
    }).catchError((e) { if (mounted) setState(() => _err = e.toString()); });
  }

  void _checkTrim() {
    if (!_isInit) return;
    final pos = _c.value.position.inMilliseconds;
    if (pos < _trim.start || pos > _trim.end) {
      _c.seekTo(Duration(milliseconds: _trim.start.toInt()));
    }
  }

  @override
  void dispose() { _c.removeListener(_checkTrim); _c.dispose(); _caption.dispose(); super.dispose(); }

  Future<void> _send() async {
    File finalFile = widget.file;
    final start = _trim.start;
    final end = _trim.end;
    
    // Only compress/trim if needed (mute or significant trim)
    if (_isMuted || start > 100 || (end < _dur.inMilliseconds - 100)) {
      setState(() => _isInit = false); // Show loading
      final info = await VideoCompress.compressVideo(
        widget.file.path,
        quality: VideoQuality.MediumQuality,
        startTime: (start / 1000).floor(),
        duration: ((end - start) / 1000).ceil(),
        includeAudio: !_isMuted,
      );
      if (info?.file != null) finalFile = info!.file!;
    }
    
    if (mounted) Navigator.pop(context, CapturedMedia(file: finalFile, type: 'video', caption: _caption.text));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        if (_isInit) Center(child: AspectRatio(aspectRatio: _c.value.aspectRatio, child: VideoPlayer(_c)))
        else if (_err != null) Center(child: Text(_err!, style: const TextStyle(color: Colors.white)))
        else const Center(child: CircularProgressIndicator(color: Colors.white)),
        
        Positioned(top: 0, left: 0, right: 0, child: SafeArea(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
            Row(children: [
              IconButton(icon: Icon(_isMuted ? Icons.volume_off : Icons.volume_up, color: Colors.white), onPressed: () { setState(() { _isMuted = !_isMuted; _c.setVolume(_isMuted ? 0 : 1); }); }),
              const IconButton(icon: Icon(Icons.content_cut, color: Colors.white), onPressed: null),
            ]),
          ]),
        ))),

        if (_isInit && _dur.inSeconds > 1) Positioned(
          top: 60, left: 16, right: 16,
          child: SafeArea(child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(12)),
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                activeTrackColor: const Color(0xFF25D366),
                inactiveTrackColor: Colors.white24,
                thumbColor: Colors.white,
                rangeThumbShape: const RoundRangeSliderThumbShape(enabledThumbRadius: 7),
              ),
              child: RangeSlider(
                values: _trim, min: 0, max: _dur.inMilliseconds.toDouble(),
                onChanged: (v) {
                  if (v.end - v.start < 1000) return;
                  setState(() => _trim = v);
                  _c.seekTo(Duration(milliseconds: v.start.toInt()));
                },
              ),
            ),
          )),
        ),

        Positioned(bottom: 20, left: 16, right: 16, child: Row(children: [
          Expanded(child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(24)),
            child: TextField(controller: _caption, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: 'Add a caption...', hintStyle: TextStyle(color: Colors.white70), border: InputBorder.none, isDense: true)),
          )),
          const SizedBox(width: 12),
          FloatingActionButton(backgroundColor: const Color(0xFF25D366), onPressed: _send, child: const Icon(Icons.send)),
        ])),
      ]),
    );
  }
}

extension on DateTime { int get msSinceEpoch => millisecondsSinceEpoch; }
