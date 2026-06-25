import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import 'package:camera_native_details/camera_native_details.dart';
import 'package:uvccamera/uvccamera.dart';
import 'photo_capture_camera_picker_screen.dart';
import 'photo_capture_preview_rotation.dart';
import 'photo_capture_uvc_device_helpers.dart';
import 'photo_capture_uvc_feed_phase.dart';
import 'photo_capture_uvc_raster_capture.dart';
import 'photo_capture_uvc_take_picture_helpers.dart';
import 'photo_capture_uvc_shutter_helpers.dart';
import 'photo_capture_view_aspect.dart';
import 'photo_capture_view_handlers.dart';
import 'photo_capture_view_layout.dart';
import 'photo_capture_view_scaffold.dart';
import 'photo_capture_viewmodel.dart';
import 'photo_model.dart';
import 'photo_image_from_xfile_io.dart' if (dart.library.html) 'photo_image_from_xfile_web.dart' as photo_image;
import '../../utils/app_runtime_config.dart';
import '../../utils/constants.dart';
import '../../utils/device_classifier.dart';
import '../../utils/logger.dart';
import '../../utils/uvc_capture_config.dart';
import '../../services/app_settings_manager.dart';
import '../../services/error_reporting/error_reporting_manager.dart';
import '../../views/widgets/app_colors.dart';
import '../../views/widgets/centered_max_width.dart';
import 'photo_capture_rotation_screen.dart';
import '../../services/hardware_key_service.dart';

class PhotoCaptureScreen extends StatefulWidget {
  const PhotoCaptureScreen({super.key});

  @override
  State<PhotoCaptureScreen> createState() => _PhotoCaptureScreenState();
}

class _PhotoCaptureScreenState extends State<PhotoCaptureScreen>
    with WidgetsBindingObserver {
  late CaptureViewModel _captureViewModel;
  StreamSubscription<HardwareKeyEvent>? _hardwareKeySub;
  bool _hardwareKeysEnabled = false;
  UvcCameraDevice? _uvcDevice;
  UvcCameraController? _uvcController;
  bool _uvcInitializing = false;
  String? _uvcError;
  bool _showCaptureFlash = false;
  StreamSubscription<UvcCameraButtonEvent>? _uvcButtonSub;
  StreamSubscription<UvcCameraStatusEvent>? _uvcStatusSub;
  StreamSubscription<UvcCameraErrorEvent>? _uvcErrorSub;
  StreamSubscription<UvcCameraDeviceEvent>? _uvcDeviceEventsSub;
  DateTime? _lastUvcShutterAt;
  bool _uvcShutterKeysEnabled = false;
  bool _uvcCaptureInFlight = false;
  UvcFeedPhase _uvcPhase = UvcFeedPhase.live;
  final GlobalKey _uvcPreviewBoundaryKey = GlobalKey();
  bool _uvcOpeningController = false;
  Timer? _uvcReconnectTimer;
  Timer? _uvcWarmupTimer;
  Timer? _uvcSessionRecycleTimer;
  DateTime? _uvcShutterGraceUntil;
  DateTime? _uvcPreviewReadyAt;
  int _uvcPreviewGeneration = 0;
  DateTime? _uvcLastUiCaptureEndedAt;
  Future<void> _uvcOp = Future<void>.value();

  bool _prefillApplied = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prefillApplied) return;
    _prefillApplied = true;
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map && args['photo'] is PhotoModel) {
      final photo = args['photo'] as PhotoModel;
      _captureViewModel.capturedPhoto = photo;
    }
  }

  Future<T> _withUvcLock<T>(Future<T> Function() fn) async {
    final gate = Completer<void>();
    final previous = _uvcOp;
    _uvcOp = gate.future;
    await previous.catchError((_) {});
    try {
      return await fn();
    } finally {
      gate.complete();
    }
  }

  void _armUvcShutterGrace() {
    _uvcShutterGraceUntil = DateTime.now().add(UvcCaptureConfig.shutterGracePeriod);
  }

  bool get _isWithinUvcShutterGrace => isWithinUvcShutterGrace(
        graceUntil: _uvcShutterGraceUntil,
      );

  bool get _uvcHoldLiveFeedClosed =>
      uvcFeedPhaseBlocksLivePreview(_uvcPhase) ||
      _uvcCaptureInFlight ||
      _captureViewModel.isCapturing ||
      _captureViewModel.capturedPhoto != null;

  bool get _uvcMayAutoOpenLiveFeed =>
      _uvcPhase == UvcFeedPhase.live &&
      !_uvcCaptureInFlight &&
      _captureViewModel.capturedPhoto == null;

  bool get _uvcBlocksConcurrentAutoOpen => uvcBlocksConcurrentAutoOpen(
        initializing: _uvcInitializing,
        openingController: _uvcOpeningController,
        phase: _uvcPhase,
      );

  bool get _uvcReadyForCapture =>
      !_uvcBlocksConcurrentAutoOpen &&
      _uvcController?.value.isInitialized == true;

  void _armUvcPreviewWarmup() {
    _uvcPreviewReadyAt = DateTime.now();
    _uvcWarmupTimer?.cancel();
    _uvcWarmupTimer = Timer(UvcCaptureConfig.previewWarmupPeriod, () {
      if (mounted) setState(() {});
    });
  }

  bool _shouldIgnorePreviewInterrupt(UvcCameraError error) {
    return shouldIgnoreUvcPreviewInterrupt(
      holdLiveFeedClosed: _uvcHoldLiveFeedClosed,
      previewWarmupActive: _uvcPreviewWarmupActive,
      reason: error.reason,
      phaseIsLive: _uvcPhase == UvcFeedPhase.live,
    );
  }

  bool get _uvcPreviewWarmupActive {
    final readyAt = _uvcPreviewReadyAt;
    if (readyAt == null) return false;
    return DateTime.now().difference(readyAt) <
        UvcCaptureConfig.previewWarmupPeriod;
  }

  void _clearUvcTransientCaptureUi() {
    _showCaptureFlash = false;
    _uvcCaptureInFlight = false;
  }

  Future<void> _pulseCaptureFlash() async {
    if (!mounted) return;
    setState(() => _showCaptureFlash = true);
    await Future<void>.delayed(UvcCaptureConfig.captureFlashDuration);
    if (!mounted) return;
    setState(() => _showCaptureFlash = false);
  }

  void _resetUvcLiveFeedSessionFlags() {
    _uvcReconnectTimer?.cancel();
    _uvcReconnectTimer = null;
    _uvcWarmupTimer?.cancel();
    _uvcWarmupTimer = null;
    _cancelUvcSessionRecycleTimer();
    _uvcShutterGraceUntil = null;
    _uvcPreviewReadyAt = null;
    _lastUvcShutterAt = null;
    _uvcLastUiCaptureEndedAt = null;
    _uvcPhase = UvcFeedPhase.live;
    _clearUvcTransientCaptureUi();
    _uvcOpeningController = false;
    _uvcInitializing = false;
  }

  void _cancelUvcSessionRecycleTimer() {
    _uvcSessionRecycleTimer?.cancel();
    _uvcSessionRecycleTimer = null;
  }

  void _armUvcSessionRecycleTimer() {
    if (!UvcCaptureConfig.enableSessionRecycle) return;
    _cancelUvcSessionRecycleTimer();
    _uvcSessionRecycleTimer = Timer(
      UvcCaptureConfig.sessionRecyclePeriod,
      _onUvcSessionRecycleTick,
    );
  }

  void _onUvcSessionRecycleTick() {
    _uvcSessionRecycleTimer = null;
    if (!mounted) return;
    if (!uvcSessionRecycleMayRun(
      sessionRecycleEnabled: UvcCaptureConfig.enableSessionRecycle,
      isUsingUvc: _isUsingUvc,
      mayAutoOpenLiveFeed: _uvcMayAutoOpenLiveFeed,
      blocksConcurrentAutoOpen: _uvcBlocksConcurrentAutoOpen,
      captureInFlight: _uvcCaptureInFlight,
      isCapturing: _captureViewModel.isCapturing,
      withinShutterGrace: _isWithinUvcShutterGrace,
    )) {
      _uvcSessionRecycleTimer = Timer(
        UvcCaptureConfig.sessionRecycleRetryDelay,
        _onUvcSessionRecycleTick,
      );
      return;
    }
    AppLogger.debug('UVC periodic session recycle');
    unawaited(_resumeUvcLiveFeed(reason: 'sessionRecycle'));
  }

  Future<XFile> _takeUvcPicture(
    UvcCameraController ctrl, {
    required String source,
  }) async {
    final attempts = uvcTakePictureAttemptsForSource(source);
    final timeout = source == 'preview_interrupt'
        ? UvcCaptureConfig.interruptTakePictureTimeout
        : UvcCaptureConfig.takePictureTimeout;
    final retryDelay = UvcCaptureConfig.interruptTakePictureRetryDelay;

    Object? lastError;
    for (var attempt = 0; attempt < attempts; attempt++) {
      final active = _uvcController;
      if (active == null || !active.value.isInitialized) {
        break;
      }
      try {
        return await active.takePicture().timeout(
          timeout,
          onTimeout: () => throw TimeoutException(
            'UVC takePicture timed out after ${timeout.inSeconds}s '
            '(source=$source attempt=${attempt + 1}/$attempts)',
          ),
        );
      } catch (e) {
        lastError = e;
        if (attempt < attempts - 1) {
          await Future<void>.delayed(retryDelay);
        }
      }
    }
    throw lastError ?? Exception('UVC takePicture failed (source=$source)');
  }

  Future<XFile> _obtainUvcStillFile(
    UvcCameraController ctrl, {
    required String source,
  }) async {
    // UVC preview is a GPU Texture — raster rarely works; plugin takePicture
    // grabs the next UVC frame (works for DSLR HDMI pause when a frame arrives).
    try {
      return await _takeUvcPicture(ctrl, source: source);
    } catch (pluginError) {
      AppLogger.error(
        'UVC takePicture failed; trying raster fallback',
        error: pluginError,
      );
      if (!uvcAllowsRasterFallback(source)) {
        rethrow;
      }
      final raster = await rasterCaptureRepaintBoundary(
        boundaryKey: _uvcPreviewBoundaryKey,
      );
      if (raster != null) {
        AppLogger.debug('UVC still from raster fallback (source=$source)');
        return raster;
      }
      rethrow;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _captureViewModel = CaptureViewModel();
    _attachUvcDeviceEvents();

    _hardwareKeySub?.cancel();
    _hardwareKeySub = HardwareKeyService.events.listen((e) async {
      if (!e.isActionDown) return;
      if (_captureViewModel.capturedPhoto != null) return;
      if (!UvcHardwareKeyCodes.isShutterKey(e.keyCode)) return;
      if (_isUsingUvc && _uvcController?.value.isInitialized == true) {
        _triggerUvcCapture(source: 'android_key_${e.keyCode}', externalSignal: true);
        return;
      }
      if (e.keyCode == UvcHardwareKeyCodes.volumeUp ||
          e.keyCode == UvcHardwareKeyCodes.volumeDown) {
        await _captureViewModel.capturePhotoWithCountdown();
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await HardwareKeyService.setEnabled(true);
      _hardwareKeysEnabled = true;
      // Await prefs before camera so SharedPreferences I/O does not overlap native
      // camera enumeration / CameraController.initialize (reduces peak contention on 2 GB devices).
      await _captureViewModel.loadPreviewRotation();
      if (!mounted) return;
      await _resetAndInitializeCameras();
    });
  }

  /// Common function to reset and initialize cameras
  /// Used both when entering the screen and when tapping the reload button
  /// Uses sync tablet check so cameras load immediately; does not block on slow getDeviceType().
  Future<void> _resetAndInitializeCameras({bool forceRefresh = false}) async {
    if (!mounted) return;

    final uvcDevice = _uvcDevice;
    if (uvcDevice != null) {
      _captureViewModel.setDeviceType(null);
      await _bindUvcDevice(uvcDevice);
      if (!mounted) return;
      try {
        final deviceType = await DeviceClassifier.getDeviceType(context);
        if (mounted) _captureViewModel.setDeviceType(deviceType);
      } catch (e, st) {
        AppLogger.error(
          'Failed to detect device type',
          error: e,
          stackTrace: st,
        );
        await ErrorReportingManager.recordError(
          e,
          st,
          reason: 'getDeviceType failed',
          fatal: false,
        );
      }
      return;
    }

    // Prefer USB/UVC DSLR when plugged in (more reliable than CameraX external).
    if (defaultTargetPlatform == TargetPlatform.android) {
      final firstUvc = await probeFirstUvcDevice();
      if (!mounted) return;
      if (firstUvc != null) {
        await _bindUvcDevice(firstUvc);
        if (!mounted) return;
        try {
          final deviceType = await DeviceClassifier.getDeviceType(context);
          if (mounted) _captureViewModel.setDeviceType(deviceType);
        } catch (e, st) {
          AppLogger.error(
            'Failed to detect device type',
            error: e,
            stackTrace: st,
          );
          await ErrorReportingManager.recordError(
            e,
            st,
            reason: 'getDeviceType failed',
            fatal: false,
          );
        }
        return;
      }
    }

    await _disposeUvc();
    _captureViewModel.setDeviceType(null);
    await _captureViewModel.resetAndInitializeCameras(
      forceRefresh: forceRefresh,
    );
    if (!mounted) return;
    // Run after camera: device_info + MediaQuery — avoids overlapping with
    // availableCameras() / initialize() native heap spike.
    try {
      final deviceType = await DeviceClassifier.getDeviceType(context);
      if (mounted) _captureViewModel.setDeviceType(deviceType);
    } catch (e, st) {
      AppLogger.error(
        'Failed to detect device type',
        error: e,
        stackTrace: st,
      );
      await ErrorReportingManager.recordError(
        e,
        st,
        reason: 'getDeviceType failed',
        fatal: false,
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _uvcReconnectTimer?.cancel();
    _uvcReconnectTimer = null;
    _uvcWarmupTimer?.cancel();
    _uvcWarmupTimer = null;
    _cancelUvcSessionRecycleTimer();
    _uvcDeviceEventsSub?.cancel();
    _uvcDeviceEventsSub = null;
    _hardwareKeySub?.cancel();
    _hardwareKeySub = null;
    if (_hardwareKeysEnabled) {
      HardwareKeyService.setEnabled(false);
    }
    if (_uvcShutterKeysEnabled) {
      HardwareKeyService.setUvcShutterKeysEnabled(false);
    }
    unawaited(_disposeUvc());
    _captureViewModel.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _isUsingUvc &&
        _uvcController == null &&
        !_uvcHoldLiveFeedClosed &&
        !_uvcBlocksConcurrentAutoOpen &&
        !_isWithinUvcShutterGrace) {
      _scheduleUvcReconnect('appResumed');
    }
  }

  @override
  void didChangeMetrics() {
    // On some Android tablets, orientation changes don't reliably update camera preview
    // unless we refresh rotation metadata. Keep this lightweight.
    _captureViewModel.refreshDisplayRotation();
  }

  Future<void> _closeUvcController() async {
    await _withUvcLock(_closeUvcControllerUnlocked);
  }

  VoidCallback? _uvcControllerListener;

  void _attachUvcControllerListener(UvcCameraController ctrl) {
    _detachUvcControllerListener();
    void listener() {
      if (!mounted) return;
      if (ctrl.value.isInitialized) {
        setState(() {});
      }
    }
    _uvcControllerListener = listener;
    ctrl.addListener(listener);
  }

  void _detachUvcControllerListener() {
    final listener = _uvcControllerListener;
    final ctrl = _uvcController;
    if (listener != null && ctrl != null) {
      ctrl.removeListener(listener);
    }
    _uvcControllerListener = null;
  }

  Future<void> _closeUvcControllerUnlocked() async {
    _detachUvcHardwareListeners();
    _detachUvcControllerListener();
    await _setUvcShutterKeysEnabled(false);
    _uvcPreviewReadyAt = null;
    final ctrl = _uvcController;
    _uvcController = null;
    if (ctrl != null) {
      try {
        await ctrl.dispose();
      } catch (_) {
        // Best-effort.
      }
    }
  }

  Future<void> _restoreUvcLiveFeedAfterRetake() async {
    _uvcPhase = UvcFeedPhase.live;
    _uvcShutterGraceUntil = null;
    _lastUvcShutterAt = null;
    _uvcError = null;
    _clearUvcTransientCaptureUi();

    final ctrl = _uvcController;
    if (UvcCaptureConfig.keepControllerOpenDuringReview &&
        ctrl != null &&
        ctrl.value.isInitialized) {
      AppLogger.debug('UVC retake: reusing open feed');
      if (mounted) setState(() {});
      return;
    }
    await _resumeUvcLiveFeed(reason: 'retake');
  }

  /// Full teardown + delay + permission nudge + reopen (retake / reconnect).
  Future<void> _resumeUvcLiveFeed({required String reason}) async {
    AppLogger.debug('UVC resume live feed ($reason)');
    if (!mounted || _uvcDevice == null) {
      return;
    }
    if (!uvcMayResumeLiveFeed(
      phase: _uvcPhase,
      hasCapturedPhoto: _captureViewModel.capturedPhoto != null,
    )) {
      return;
    }

    _uvcReconnectTimer?.cancel();
    _uvcShutterGraceUntil = null;
    _lastUvcShutterAt = null;
    _clearUvcTransientCaptureUi();
    _uvcPhase = UvcFeedPhase.live;

    if (!mounted) return;
    setState(() {
      _uvcError = null;
      _uvcInitializing = true;
    });

    try {
      await _withUvcLock(_closeUvcControllerUnlocked);
      if (!UvcCaptureConfig.keepControllerOpenDuringReview) {
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
      }
      await Future<void>.delayed(UvcCaptureConfig.reopenFeedDelay);
      if (!mounted || _uvcDevice == null || !_uvcMayAutoOpenLiveFeed) {
        return;
      }

      final device = _uvcDevice!;
      final permitted = await ensureUvcPermissions(device);
      if (!mounted) return;
      if (!permitted) {
        setState(() {
          _uvcPhase = UvcFeedPhase.error;
          _uvcError = 'USB camera permission was not granted.';
        });
        return;
      }

      await _openUvcController();
      if (!mounted) return;
      if (_uvcController == null &&
          _uvcPhase == UvcFeedPhase.live &&
          _uvcError == null) {
        _uvcPhase = UvcFeedPhase.error;
        setState(() {
          _uvcError = 'USB camera did not reopen. Tap Retry USB camera.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _uvcInitializing = false);
      }
    }
  }

  Future<void> _disposeUvc() async {
    _resetUvcLiveFeedSessionFlags();
    await _closeUvcController();
    _uvcDevice = null;
    _uvcError = null;
    _uvcPreviewGeneration = 0;
  }

  bool get _isUsingUvc => _uvcDevice != null;

  void _attachUvcDeviceEvents() {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    _uvcDeviceEventsSub?.cancel();
    _uvcDeviceEventsSub = UvcCamera.deviceEventStream.listen(
      _onUvcDeviceEvent,
      onError: (err, st) {
        AppLogger.error('UVC deviceEventStream error', error: err, stackTrace: st);
      },
    );
  }

  void _onUvcDeviceEvent(UvcCameraDeviceEvent event) {
    final bound = _uvcDevice;
    if (bound == null || !uvcDeviceMatches(event.device, bound)) return;

    AppLogger.debug(
      'UVC device event: ${event.type.name} '
      'name="${event.device.name}" vid=${event.device.vendorId} pid=${event.device.productId}',
    );

    switch (event.type) {
      case UvcCameraDeviceEventType.attached:
        if (_uvcMayAutoOpenLiveFeed &&
            _uvcController == null &&
            !_uvcBlocksConcurrentAutoOpen) {
          _scheduleUvcReconnect('attached');
        }
      case UvcCameraDeviceEventType.connected:
        if (_uvcMayAutoOpenLiveFeed &&
            _uvcController == null &&
            !_uvcBlocksConcurrentAutoOpen) {
          unawaited(_openUvcController());
        }
      case UvcCameraDeviceEventType.disconnected:
      case UvcCameraDeviceEventType.detached:
        if (_uvcHoldLiveFeedClosed ||
            _isWithinUvcShutterGrace ||
            _uvcPhase != UvcFeedPhase.live) {
          return;
        }
        unawaited(() async {
          await _closeUvcController();
          if (!mounted) return;
          setState(() {
            _uvcInitializing = false;
            _uvcOpeningController = false;
            _uvcError = 'USB camera disconnected. Reconnecting…';
          });
          _scheduleUvcReconnect(event.type.name);
        }());
    }
  }

  void _scheduleUvcReconnect(String reason) {
    if (!_isUsingUvc ||
        !_uvcMayAutoOpenLiveFeed ||
        _uvcBlocksConcurrentAutoOpen) {
      return;
    }
    _uvcReconnectTimer?.cancel();
    _uvcReconnectTimer = Timer(const Duration(milliseconds: 650), () {
      if (!mounted) return;
      if (_uvcDevice == null ||
          _uvcController != null ||
          !_uvcMayAutoOpenLiveFeed ||
          _uvcBlocksConcurrentAutoOpen) {
        return;
      }
      AppLogger.debug('UVC reconnect scheduled ($reason)');
      unawaited(_resumeUvcLiveFeed(reason: reason));
    });
  }

  Future<void> _bindUvcDevice(UvcCameraDevice device) async {
    if (_uvcCaptureInFlight || _captureViewModel.capturedPhoto != null) return;

    _captureViewModel.applyDefaultPreviewRotationForUvc();
    await _captureViewModel.disposeCamera();

    if (!mounted) return;
    setState(() {
      _uvcDevice = device;
      _uvcError = null;
    });

    final ok = await ensureUvcPermissions(device);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _uvcInitializing = false;
        _uvcError = 'USB camera permission was not granted.';
      });
      return;
    }

    await _openUvcController();
  }

  Future<void> _openUvcController() async {
    await _withUvcLock(() async {
      final device = _uvcDevice;
      if (device == null || !mounted) return;
      if (_uvcOpeningController || !_uvcMayAutoOpenLiveFeed) {
        return;
      }
      if (_isWithinUvcShutterGrace) {
        return;
      }
      if (_uvcController != null && _uvcController!.value.isInitialized) return;

      _uvcOpeningController = true;
      await _closeUvcControllerUnlocked();
      if (!mounted) {
        return;
      }

      setState(() {
        _uvcInitializing = true;
        _uvcError = null;
      });

      UvcCameraController? opened;
      try {
        final ctrl = UvcCameraController(
          device: device,
          resolutionPreset: UvcCaptureConfig.resolutionPreset,
        );
        await ctrl.initialize();
        if (!mounted) return;
        await _captureViewModel.refreshDisplayRotation();
        if (!mounted) return;
        opened = ctrl;
        _uvcPreviewGeneration++;
        _armUvcPreviewWarmup();
        setState(() {
          _uvcController = ctrl;
          _uvcInitializing = false;
          _uvcError = null;
          _uvcPhase = UvcFeedPhase.live;
        });
        _attachUvcHardwareListeners(ctrl);
        await _setUvcShutterKeysEnabled(true);
        _armUvcSessionRecycleTimer();
        AppLogger.debug(
          'UVC preview opened preset=${UvcCaptureConfig.resolutionPreset.name} '
          'gen=$_uvcPreviewGeneration',
        );
      } catch (e, st) {
        AppLogger.error('UVC open failed (main preview)', error: e, stackTrace: st);
        if (!mounted) return;
        setState(() {
          _uvcInitializing = false;
          _uvcPhase = UvcFeedPhase.error;
          _uvcError = 'Failed to initialize USB camera: $e';
        });
      } finally {
        _uvcOpeningController = false;
        if (mounted && opened == null) {
          setState(() => _uvcInitializing = false);
        }
      }
    });
  }

  Future<void> _setUvcShutterKeysEnabled(bool enabled) async {
    if (_uvcShutterKeysEnabled == enabled) return;
    _uvcShutterKeysEnabled = enabled;
    await HardwareKeyService.setUvcShutterKeysEnabled(enabled);
  }

  void _detachUvcHardwareListeners() {
    _uvcButtonSub?.cancel();
    _uvcButtonSub = null;
    _uvcStatusSub?.cancel();
    _uvcStatusSub = null;
    _uvcErrorSub?.cancel();
    _uvcErrorSub = null;
  }

  void _triggerUvcCapture({
    required String source,
    int button = 0,
    int state = 1,
    bool externalSignal = false,
  }) {
    AppLogger.debug('UVC shutter signal source=$source btn=$button state=$state');
    if (!mounted) return;
    if (_uvcHoldLiveFeedClosed) {
      return;
    }
    if (_uvcController == null || !_uvcController!.value.isInitialized) {
      return;
    }
    if (_uvcPreviewWarmupActive && externalSignal) {
      AppLogger.debug('UVC shutter ignored during preview warmup source=$source');
      return;
    }
    if (!shouldTriggerUvcShutterCapture(
      button: button,
      state: state,
      lastCaptureAt: _lastUvcShutterAt,
      externalSignal: externalSignal,
    )) {
      return;
    }
    _lastUvcShutterAt = DateTime.now();
    _armUvcShutterGrace();
    _uvcReconnectTimer?.cancel();
    unawaited(_captureUvc(_captureViewModel, source: source));
  }

  void _attachUvcHardwareListeners(UvcCameraController ctrl) {
    _detachUvcHardwareListeners();
    _attachUvcControllerListener(ctrl);
    _uvcButtonSub = ctrl.cameraButtonEvents.listen((event) {
      _triggerUvcCapture(
        source: 'uvc_button',
        button: event.button,
        state: event.state,
      );
    });
    _uvcStatusSub = ctrl.cameraStatusEvents.listen((event) {
      AppLogger.debug(
        'UVC status class=${event.payload.statusClass.name} '
        'event=${event.payload.event} selector=${event.payload.selector}',
      );
    });
    _uvcErrorSub = ctrl.cameraErrorEvents.listen((event) {
      if (event.error.type != UvcCameraErrorType.previewInterrupted) return;
      AppLogger.debug(
        'UVC previewInterrupted reason=${event.error.reason}',
      );
      if (_shouldIgnorePreviewInterrupt(event.error)) {
        AppLogger.debug('UVC previewInterrupted ignored');
        return;
      }
      if (!shouldTriggerUvcShutterFromInterrupt(lastCaptureAt: _lastUvcShutterAt)) {
        AppLogger.debug('UVC previewInterrupted debounced');
        return;
      }
      _lastUvcShutterAt = DateTime.now();
      _armUvcShutterGrace();
      _uvcReconnectTimer?.cancel();
      // DSLR clean-HDMI: body shutter pauses the feed — capture like UI button.
      unawaited(_captureUvc(
        _captureViewModel,
        source: 'preview_interrupt',
      ));
    });
  }

  Future<void> _showCameraSelectionDialog(
    BuildContext context,
    CaptureViewModel viewModel,
  ) async {
    final picked = await Navigator.of(context).push<Object?>(
      MaterialPageRoute<Object?>(
        builder: (_) => PhotoCaptureCameraPickerScreen(viewModel: viewModel),
      ),
    );
    if (!mounted || picked == null) return;

    if (picked is CameraDescription) {
      await _disposeUvc();
      await viewModel.switchCamera(picked);
      return;
    }

    if (picked is UvcCameraDevice) {
      await _bindUvcDevice(picked);
    }
  }

  Size? _uvcPreviewDisplaySize(CaptureViewModel viewModel) {
    final mode = _uvcController?.value.previewMode;
    if (mode == null) return null;
    return viewModel.uvcPreviewDisplaySizeForCard(
      frameWidth: mode.frameWidth.toDouble(),
      frameHeight: mode.frameHeight.toDouble(),
    );
  }

  Widget _buildUvcPreview(BuildContext context, CaptureViewModel viewModel) {
    // Spinner while grabbing still or normalizing (matches in-app Capture UX).
    if ((viewModel.isCapturing || _uvcCaptureInFlight) &&
        viewModel.capturedPhoto == null) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 12),
              Text(
                'Saving photo…',
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      );
    }

    final ctrl = _uvcController;
    if (_uvcInitializing) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    if (_uvcError != null) {
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _uvcError!,
                  style: const TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: _uvcInitializing || _uvcOpeningController
                      ? null
                      : () => unawaited(_resumeUvcLiveFeed(reason: 'retryTap')),
                  child: const Text('Retry USB camera'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (ctrl == null || !ctrl.value.isInitialized) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 12),
              Text(
                'Connecting USB camera…',
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      );
    }

    return ValueListenableBuilder<UvcCameraControllerState>(
      valueListenable: ctrl,
      builder: (context, state, _) {
        if (!state.isInitialized) {
          return const ColoredBox(
            color: Colors.black,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 12),
                  Text(
                    'Connecting USB camera…',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          );
        }

        final previewMode = state.previewMode;
        final frameWidth = previewMode?.frameWidth.toDouble() ?? 1.0;
        final frameHeight = previewMode?.frameHeight.toDouble() ?? 1.0;
        final baseAspect = frameWidth / frameHeight;
        final effectiveTurns = viewModel.uvcPreviewEffectiveQuarterTurns;

        return KeyedSubtree(
          key: ValueKey<int>(_uvcPreviewGeneration),
          child: RepaintBoundary(
            key: _uvcPreviewBoundaryKey,
            child: buildRotatedCoverPreview(
              preview: ctrl.buildPreview(),
              effectiveQuarterTurns: effectiveTurns,
              baseAspectRatio: baseAspect <= 0 ? 1.0 : baseAspect,
              frameSize: Size(frameWidth, frameHeight),
            ),
          ),
        );
      },
    );
  }

  Future<void> _captureUvc(
    CaptureViewModel viewModel, {
    required String source,
  }) async {
    await _withUvcLock(() async {
      final ctrl = _uvcController;
      final device = _uvcDevice;
      if (ctrl == null ||
          device == null ||
          _uvcPhase == UvcFeedPhase.capturing ||
          _uvcPhase == UvcFeedPhase.reviewing ||
          viewModel.capturedPhoto != null ||
          viewModel.isCapturing) {
        return;
      }
      if (!isUvcShutterCaptureSource(source) && !_uvcReadyForCapture) {
        return;
      }
      if (source == 'ui_button' && _uvcLastUiCaptureEndedAt != null) {
        final elapsed = DateTime.now().difference(_uvcLastUiCaptureEndedAt!);
        final cooldown = UvcCaptureConfig.uiCaptureCooldown;
        if (elapsed < cooldown) {
          await Future<void>.delayed(cooldown - elapsed);
          if (!mounted) return;
        }
      }
      if (isUvcShutterCaptureSource(source) &&
          (ctrl.value.isInitialized != true || _uvcBlocksConcurrentAutoOpen)) {
        return;
      }

      if (isUvcShutterCaptureSource(source)) {
        final now = DateTime.now();
        if (_lastUvcShutterAt != null &&
            now.difference(_lastUvcShutterAt!) < kUvcShutterDebounce) {
          AppLogger.debug('UVC capture debounced source=$source');
          return;
        }
        _lastUvcShutterAt = now;
        _armUvcShutterGrace();
      }

      _uvcPhase = UvcFeedPhase.capturing;
      _uvcCaptureInFlight = true;
      _uvcReconnectTimer?.cancel();
      if (mounted) setState(() {});
      final cameraId =
          'uvc:${device.vendorId}:${device.productId}:${device.name}';
      var captureSucceeded = false;

      try {
        AppLogger.debug('UVC capture start source=$source');
        await _pulseCaptureFlash();
        final previewMode = ctrl.value.previewMode;
        if (previewMode != null) {
          final displaySize = viewModel.uvcPreviewDisplaySizeForCard(
            frameWidth: previewMode.frameWidth.toDouble(),
            frameHeight: previewMode.frameHeight.toDouble(),
          );
          if (displaySize != null && displaySize.height > 0) {
            viewModel.lockCaptureCardAspectRatio(
              displaySize.width / displaySize.height,
            );
          }
        }

        if (!isUvcShutterCaptureSource(source)) {
          await Future<void>.delayed(UvcCaptureConfig.preCaptureSettleDelay);
        }
        await Future<void>.delayed(Duration.zero);
        final file = await _obtainUvcStillFile(ctrl, source: source);
        if (mounted) setState(() => _showCaptureFlash = false);

        final keepFeedOpen = UvcCaptureConfig.keepControllerOpenDuringReview;
        if (!keepFeedOpen) {
          _detachUvcHardwareListeners();
          await _closeUvcControllerUnlocked();
          await Future<void>.delayed(UvcCaptureConfig.postDisposeDelay);
          if (mounted) setState(() {});
        }

        await viewModel.setCapturedPhotoFromExternalFile(
          rawFile: file,
          cameraId: cameraId,
          force: true,
        );
        if (!mounted) return;
        if (viewModel.capturedPhoto == null) {
          _uvcPhase = UvcFeedPhase.error;
          setState(() {
            _uvcError = viewModel.errorMessage ??
                'USB camera capture failed. Tap Retry USB camera.';
          });
          return;
        }
        captureSucceeded = true;
        _uvcPhase = UvcFeedPhase.reviewing;
        _uvcReconnectTimer?.cancel();
        if (source == 'ui_button') {
          _uvcLastUiCaptureEndedAt = DateTime.now();
        }
      } catch (e, st) {
        AppLogger.error(
          'UVC capture failed source=$source',
          error: e,
          stackTrace: st,
        );
        if (!mounted) return;
        _uvcPhase = UvcFeedPhase.error;
        setState(() {
          _uvcError = isUvcShutterCaptureSource(source)
              ? 'DSLR shutter capture failed. Tap Retry USB camera, or use Capture on screen.'
              : 'USB camera capture failed: $e';
        });
      } finally {
        if (!captureSucceeded && _uvcPhase != UvcFeedPhase.reviewing) {
          _detachUvcHardwareListeners();
          await _closeUvcControllerUnlocked();
        }
        _clearUvcTransientCaptureUi();
        if (mounted) setState(() {});
      }
    });
  }

  Future<void> _openPreviewRotationScreen(BuildContext context, CaptureViewModel viewModel) async {
    final result = await Navigator.of(context).push<int>(
      MaterialPageRoute<int>(
        builder: (ctx) => PhotoCaptureRotationScreen(
          currentRotation: viewModel.previewRotationDegrees,
        ),
      ),
    );
    if (result != null && mounted) {
      await viewModel.setPreviewRotation(result);
    }
  }

  Widget _buildNoCamerasYetState(BuildContext context) {
    final allowGallery = context.select<AppSettingsManager, bool>(
      (m) => m.settings?.photoUploadAllowed == true,
    );
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 16),
            Text(
              allowGallery
                  ? 'Waiting for camera… or use Gallery below if this takes too long.'
                  : 'Waiting for camera…',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 15,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => _resetAndInitializeCameras(forceRefresh: true),
              child: const Text('Retry camera'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetectingCamerasState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: Colors.white),
          const SizedBox(height: 20),
          Text(
            'Detecting cameras…',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCaptureFatalErrorState(
    BuildContext context,
    CaptureViewModel viewModel,
  ) {
    final appColors = AppColors.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            CupertinoIcons.exclamationmark_triangle,
            size: 64,
            color: appColors.errorColor,
          ),
          const SizedBox(height: 16),
          Text(
            viewModel.errorMessage ?? 'Unknown error',
            style: const TextStyle(fontSize: 16, color: Colors.white),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: () => _resetAndInitializeCameras(forceRefresh: true),
                child: const Text('Retry'),
              ),
              TextButton(
                onPressed: () => openAppSettings(),
                child: const Text('Open Settings'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCaptureBodyContent(
    BuildContext context,
    CaptureViewModel viewModel,
  ) {
    if (viewModel.isLoadingCameras) return _buildDetectingCamerasState();
    if (viewModel.isInitializing) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    if (viewModel.availableCameras.isEmpty && !viewModel.hasError && !_isUsingUvc) {
      return _buildNoCamerasYetState(context);
    }
    if (viewModel.hasError && viewModel.capturedPhoto == null && !_isUsingUvc) {
      return _buildCaptureFatalErrorState(context, viewModel);
    }
    if (!_isUsingUvc && !viewModel.isReady && viewModel.capturedPhoto == null) {
      return const Center(
        child: Text(
          'Camera not ready',
          style: TextStyle(color: Colors.white),
        ),
      );
    }

    final previewWidget = _isUsingUvc
        ? _buildUvcPreview(context, viewModel)
        : _buildCameraPreviewWithRotation(context, viewModel);
    final hasCapturedPhoto = viewModel.capturedPhoto != null;
    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 12),
      child: _buildCaptureColumn(
        context: context,
        viewModel: viewModel,
        hasCapturedPhoto: hasCapturedPhoto,
        previewWidget: previewWidget,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _captureViewModel,
      child: Consumer<CaptureViewModel>(
        builder: (context, viewModel, child) {
          return ListenableBuilder(
            listenable: AppRuntimeConfig.instance,
            builder: (context, _) {
              return PhotoCaptureScaffold(
                viewModel: viewModel,
                onBack: () => Navigator.pop(context),
                onSelectCamera: () =>
                    _showCameraSelectionDialog(context, viewModel),
                onOpenRotation: () =>
                    _openPreviewRotationScreen(context, viewModel),
                onReloadCameras: () =>
                    _resetAndInitializeCameras(forceRefresh: true),
                body: Builder(
                  builder: (context) => _buildCaptureBodyContent(
                    context,
                    Provider.of<CaptureViewModel>(context, listen: true),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  /// Column layout for both orientations: info at top, buttons row, preview/photo fills rest.
  Widget _buildCaptureColumn({
    required BuildContext context,
    required CaptureViewModel viewModel,
    required bool hasCapturedPhoto,
    required Widget previewWidget,
  }) {
    final showNativeDetails = !_isUsingUvc &&
        AppConstants.kShowNativeCameraInfoPane &&
        viewModel.nativeCameraDetails != null &&
        !hasCapturedPhoto;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Camera info (pre-capture) or captured photo info (post-capture) at top
        if (showNativeDetails)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _buildNativeCameraDetailsCard(
              context,
              viewModel.nativeCameraDetails!,
              previewSize: viewModel.previewSize,
              resolutionPreset: viewModel.effectiveResolutionPreset,
              currentZoom: viewModel.currentZoom,
            ),
          ),
        if (hasCapturedPhoto &&
            AppConstants.kShowNativeCameraInfoPane)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (AppConstants.kShowNativeCameraInfoPane)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _effectiveRotationLabel(viewModel),
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ),
              ],
            ),
          ),
        // 2. Preview or captured photo: same aspect as theme hero card; size capped so landscape matches carousel scale.
        Expanded(
          child: _buildCapturePreviewCard(
            context,
            viewModel,
            previewWidget,
            hasCapturedPhoto,
          ),
        ),
        // 3. Post-capture errors (e.g. upload) above Continue — full-screen branch is skipped when a photo exists.
        if (hasCapturedPhoto && viewModel.hasError && viewModel.errorMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _buildCaptureErrorSection(context, viewModel),
          ),
        // 4. Bottom actions (consistent placement).
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: CenteredMaxWidth(
            maxWidth: 360,
            child: hasCapturedPhoto
                ? _buildCapturedPhotoControlsRow(context, viewModel)
                : _buildGalleryCaptureButtonsRow(context, viewModel),
          ),
        ),
      ],
    );
  }

  /// Preview / captured still: [ThemeCard]-style shell. Card **aspect** follows the stream or file
  /// when known (landscape webcam → landscape frame; portrait → portrait) so web/mobile avoid
  /// heavy letterboxing. Falls back to [AppConstants.themeCardSlotAspectRatio] if size unknown.
  ///
  /// Size is capped on width/height so landscape kiosks get a bounded card.
  Widget _buildCapturePreviewCard(
    BuildContext context,
    CaptureViewModel viewModel,
    Widget previewWidget,
    bool hasCapturedPhoto,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final media = MediaQuery.sizeOf(context);
        final isLandscape =
            MediaQuery.orientationOf(context) == Orientation.landscape;
        final isTablet = media.shortestSide >= AppConstants.kTabletBreakpoint;
        final fallbackAspect = AppConstants.themeCardSlotAspectRatio(context);
        final isPhonePortrait = !isLandscape &&
            media.shortestSide < AppConstants.kTabletBreakpoint;
        final aspect = captureCardAspectRatio(
          context,
          viewModel,
          hasCapturedPhoto,
          fallbackAspect,
          constraints,
          uvcPreviewDisplaySize:
              _isUsingUvc ? _uvcPreviewDisplaySize(viewModel) : null,
        );

        final (widthCapFrac, heightCapFrac) = capturePreviewCardSizeFractions(
          isLandscape: isLandscape,
          isPhonePortrait: isPhonePortrait,
        );

        // Tablets: use the full canvas available for a cleaner kiosk-style preview.
        final maxW = isTablet
            ? constraints.maxWidth
            : math.min(constraints.maxWidth, media.width * widthCapFrac);
        final maxH = isTablet
            ? constraints.maxHeight
            : math.min(constraints.maxHeight, media.height * heightCapFrac);

        final (cardW, cardH) = capturePreviewCardDimensions(
          constraints: constraints,
          aspect: aspect,
          maxW: maxW,
          maxH: maxH,
        );

        return Center(
          child: Card(
            margin: EdgeInsets.zero,
            elevation: 8,
            shadowColor: Colors.black.withValues(alpha: 0.38),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(
                color: Color(0xFF4A4A4A),
                width: 1.5,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: cardW,
              height: cardH,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: Colors.black,
                    child: KeyedSubtree(
                      key: ValueKey<String>(
                        viewModel.capturedPhoto?.id ?? 'live-preview',
                      ),
                      child: viewModel.capturedPhoto != null
                          ? photo_image.imageFromXFileSized(
                              viewModel.capturedPhoto!.imageFile,
                              cardW,
                              cardH,
                              // Match live preview: full-bleed cover (no black “stencil”), smooth shutter transition.
                              fit: BoxFit.cover,
                            )
                          : KeyedSubtree(
                              // Web builds can aggressively reuse platform views / textures.
                              // Force the camera preview subtree to remount on retake.
                              key: ValueKey<int>(viewModel.previewNonce),
                              child: previewWidget,
                            ),
                    ),
                  ),
                  if (!hasCapturedPhoto &&
                      AppConstants.kShowNativeCameraInfoPane &&
                      (_isUsingUvc || viewModel.previewSize != null))
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _effectiveRotationLabel(viewModel),
                          style: const TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ),
                    ),
                  if (viewModel.isCountingDown)
                    Positioned.fill(
                      child: _buildCountdownOverlay(context, viewModel.countdownValue!),
                    ),
                  if (!_showCaptureFlash &&
                      !hasCapturedPhoto &&
                      (viewModel.isCapturing || _uvcCaptureInFlight))
                    Positioned.fill(
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: 0.35),
                        child: const Center(
                          child: CircularProgressIndicator(
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  if (_showCaptureFlash)
                    Positioned.fill(
                      child: const ColoredBox(color: Colors.white),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Builds camera preview and applies Android TV/external-camera correction
  /// plus any user-selected manual rotation.
  Widget _buildCameraPreviewWithRotation(BuildContext context, CaptureViewModel viewModel) {
    final controller = viewModel.cameraController;
    if (controller == null) {
      return Container(
        color: AppColors.of(context).backgroundColor,
        child: Center(
          child: Text(
            'Camera preview not available',
            style: TextStyle(color: AppColors.of(context).textColor),
          ),
        ),
      );
    }

    final preview = _buildPlatformPreview(controller);
    final effectiveQuarterTurns =
        (viewModel.previewAutoQuarterTurns +
                (viewModel.previewRotationDegrees ~/ 90) % 4) %
            4;
    final baseAspectRatio = controller.value.aspectRatio;

    return buildRotatedCoverPreview(
      preview: preview,
      effectiveQuarterTurns: effectiveQuarterTurns,
      baseAspectRatio: baseAspectRatio,
      frameSize: controller.value.previewSize,
    );
  }

  Widget _buildPlatformPreview(CameraController controller) {
    return CameraPreview(controller);
  }

  String _effectiveRotationLabel(CaptureViewModel viewModel) {
    if (_isUsingUvc) {
      final autoTurns = viewModel.uvcPreviewAutoQuarterTurns;
      final manualTurns = (viewModel.previewRotationDegrees ~/ 90) % 4;
      final effectiveTurns = (autoTurns + manualTurns) % 4;
      final rotation =
          '${effectiveTurns * 90}° (auto ${autoTurns * 90}° + manual ${manualTurns * 90}°)';
      final mode = _uvcController?.value.previewMode;
      if (mode != null) {
        return '$rotation • ${mode.frameWidth}×${mode.frameHeight}';
      }
      return '$rotation • USB';
    }

    final autoTurns = viewModel.previewAutoQuarterTurns;
    final manualTurns = (viewModel.previewRotationDegrees ~/ 90) % 4;
    final effectiveTurns = (autoTurns + manualTurns) % 4;
    final rotation = '${effectiveTurns * 90}° (auto ${autoTurns * 90}° + manual ${manualTurns * 90}°)';
    final size = viewModel.previewSize;
    if (size != null) {
      return '$rotation • ${size.width.toInt()}×${size.height.toInt()}';
    }
    return rotation;
  }

  /// Native camera details pane (preview size, active array, zoom, etc.). Shown until photo is captured.
  Widget _buildNativeCameraDetailsCard(
    BuildContext context,
    CameraDetails details, {
    Size? previewSize,
    ResolutionPreset? resolutionPreset,
    double? currentZoom,
  }) {
    const style = TextStyle(color: Colors.white70, fontSize: 11);
    const labelStyle = TextStyle(color: Colors.white54, fontSize: 10);
    final inUseW = previewSize?.width.toInt();
    final inUseH = previewSize?.height.toInt();
    final presetName = resolutionPreset?.name ?? '?';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      constraints: const BoxConstraints(maxWidth: 260),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Native camera (${details.platform})', style: style.copyWith(fontWeight: FontWeight.w600)),
          if (inUseW != null && inUseH != null)
            _detailRow('Preview in use', '$inUseW×$inUseH ($presetName)', labelStyle, style),
          if (currentZoom != null)
            _detailRow('Current zoom', '${currentZoom.toStringAsFixed(2)}x', labelStyle, style),
          const SizedBox(height: 6),
          if (details.activeArrayWidth != null && details.activeArrayHeight != null)
            _detailRow('Active array', '${details.activeArrayWidth}×${details.activeArrayHeight}', labelStyle, style),
          if (details.zoomRatioRangeMin != null && details.zoomRatioRangeMax != null)
            _detailRow('Zoom ratio', '${details.zoomRatioRangeMin!.toStringAsFixed(2)} – ${details.zoomRatioRangeMax!.toStringAsFixed(2)}', labelStyle, style),
          if (details.maxDigitalZoom != null)
            _detailRow('Max digital zoom', details.maxDigitalZoom!.toStringAsFixed(2), labelStyle, style),
          if (details.lensFacing != null)
            _detailRow('Lens facing', details.lensFacing!, labelStyle, style),
          const SizedBox(height: 4),
          Text('Preview sizes (${details.supportedPreviewSizes.length})', style: labelStyle),
          Text(details.supportedPreviewSizes.isEmpty ? '—' : details.supportedPreviewSizes.join(', '), style: style),
          const SizedBox(height: 2),
          Text('Capture sizes (${details.supportedCaptureSizes.length})', style: labelStyle),
          Text(details.supportedCaptureSizes.isEmpty ? '—' : details.supportedCaptureSizes.join(', '), style: style),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value, TextStyle labelStyle, TextStyle valueStyle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 110, child: Text(label, style: labelStyle)),
          Expanded(child: Text(value, style: valueStyle)),
        ],
      ),
    );
  }

  /// Builds the on-screen capture countdown overlay (e.g. 5, 4, 3…).
  Widget _buildCountdownOverlay(BuildContext context, int countdownValue) {
    return Container(
      color: Colors.black.withValues(alpha: 0.5),
      child: Center(
        child: Container(
          width: 150,
          height: 150,
          decoration: BoxDecoration(
            color: Colors.grey.withValues(alpha: 0.7),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 30,
                spreadRadius: 10,
              ),
            ],
          ),
          child: Center(
            child: Text(
              '$countdownValue',
              style: const TextStyle(
                fontSize: 80,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Retake and Continue buttons in a Row (post-capture).
  Widget _buildCapturedPhotoControlsRow(BuildContext context, CaptureViewModel viewModel) {
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ElevatedButton(
            style: captureScreenButtonStyle(secondary: true),
            onPressed: () async {
              await handleCapturedPhotoRetake(
                context: context,
                viewModel: viewModel,
                isMounted: () => mounted,
              );
              if (mounted && _uvcDevice != null) {
                await _restoreUvcLiveFeedAfterRetake();
              }
            },
            child: const Text('Retake'),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            style: captureScreenButtonStyle(),
            onPressed: viewModel.canContinueUpload
                ? () => handleCapturedPhotoContinue(
                      context: context,
                      viewModel: viewModel,
                      isMounted: () => mounted,
                    )
                : null,
            child: viewModel.isUploading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : Text(
                    viewModel.isPreparingUploadPayload
                        ? 'Preparing…'
                        : 'Continue',
                  ),
          ),
        ],
      ),
    );
  }

  /// Error message + Dismiss, shown inside blue box when capture has error.
  Widget _buildCaptureErrorSection(BuildContext context, CaptureViewModel viewModel) {
    final appColors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: appColors.errorColor.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(CupertinoIcons.exclamationmark_triangle, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text('Error', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            viewModel.errorMessage!,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: () {
              if (viewModel.capturedPhoto != null) {
                viewModel.clearErrorMessage();
              } else {
                viewModel.clearCapturedPhoto();
              }
            },
            child: Text('Dismiss', style: TextStyle(color: appColors.errorColor, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  /// Gallery and Capture buttons in a Row (pre-capture).
  Widget _buildGalleryCaptureButtonsRow(BuildContext context, CaptureViewModel viewModel) {
    final isPhotoUploadAllowed = context.select<AppSettingsManager, bool>(
      (settingsManager) => settingsManager.settings?.photoUploadAllowed == true,
    );

    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isPhotoUploadAllowed) ...[
            ElevatedButton.icon(
              style: captureScreenButtonStyle(secondary: true),
              onPressed:
                  (viewModel.isCapturing || viewModel.isSelectingFromGallery)
                      ? null
                      : () async => await viewModel.selectFromGallery(),
              icon: viewModel.isSelectingFromGallery
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(CupertinoIcons.photo, size: 20),
              label: const Text('Gallery'),
            ),
            const SizedBox(height: 12),
          ],
          ElevatedButton.icon(
            style: captureScreenButtonStyle(),
            onPressed: (viewModel.isCapturing ||
                    _uvcCaptureInFlight ||
                    viewModel.isSelectingFromGallery ||
                    viewModel.isCountingDown ||
                    (_isUsingUvc && !_uvcReadyForCapture))
                ? null
                : () async {
                    if (_isUsingUvc) {
                      await viewModel.captureWithCountdown(
                        () => _captureUvc(viewModel, source: 'ui_button'),
                        canStart: () =>
                            _uvcReadyForCapture && !_uvcCaptureInFlight,
                      );
                    } else {
                      await viewModel.capturePhotoWithCountdown();
                    }
                  },
            icon: (viewModel.isCapturing || _uvcCaptureInFlight)
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(CupertinoIcons.camera, size: 20),
            label: const Text('Capture'),
          ),
        ],
      ),
    );
  }
}
