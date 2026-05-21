import 'dart:async';
import 'dart:ui'
    show Size, ImmutableBuffer, instantiateImageCodecFromBuffer;
import 'package:flutter/foundation.dart' show ChangeNotifier, TargetPlatform, compute, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart' show DeviceOrientation, MethodChannel;
import 'package:camera/camera.dart';
import 'package:camera/camera.dart' as cam show availableCameras;
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'photo_model.dart';
import '../../services/api_service.dart';
import '../../services/file_helper.dart';
import '../../services/session_manager.dart';
import '../../utils/constants.dart';
import '../../utils/device_classifier.dart';
import '../../utils/app_device_type.dart';
import '../../utils/exceptions.dart' as app_exceptions;
import '../../utils/image_helper.dart';
import 'camera_description_label.dart';
import '../../utils/app_strings.dart';
import '../../utils/logger.dart';
import '../../utils/web_flow_trace.dart';
import '../../services/error_reporting/error_reporting_manager.dart';
import 'package:camera_native_details/camera_native_details.dart';
import 'camera_image_yuv_jpeg.dart';
import 'photo_capture_camera_config.dart';

(double, double) _previewDisplayDimensions({
  required Size? previewSize,
  required int effectiveQuarterTurns,
  required double displayAspectRatio,
}) {
  final odd = effectiveQuarterTurns.isOdd;
  if (previewSize == null) {
    return odd ? (1.0, displayAspectRatio) : (displayAspectRatio, 1.0);
  }
  return odd
      ? (previewSize.height, previewSize.width)
      : (previewSize.width, previewSize.height);
}

class CaptureViewModel extends ChangeNotifier {
  final ApiService _apiService;
  final SessionManager _sessionManager;
  final Uuid _uuid = const Uuid();
  static List<CameraDescription>? _cachedAvailableCameras;
  CameraController? _cameraController;

  /// Preloads camera list in main() (like the camera package example).
  /// Only caches when list is non-empty so Android without permission still does full load on screen open.
  static Future<void> preloadCameras() async {
    try {
      final list = await cam.availableCameras();
      if (list.isNotEmpty) {
        _cachedAvailableCameras = List<CameraDescription>.from(list);
      }
    } on Exception {
      _cachedAvailableCameras = null;
    }
  }
  PhotoModel? _capturedPhoto;
  /// Decoded pixel size of [_capturedPhoto] (for UI card aspect). Null until decode finishes.
  Size? _capturedImagePixelSize;
  /// Aspect ratio (width/height) of the **live preview** at shutter time. Keeps the card
  /// from resizing when the saved still has different pixel dimensions than the stream.
  double? _lockedCaptureCardAspectRatio;
  List<CameraDescription> _availableCameras = [];
  CameraDescription? _currentCamera;
  AppDeviceType? _deviceType;
  bool _isLoadingCameras = false;
  bool _isInitializing = false;
  bool _isCapturing = false;
  bool _isSelectingFromGallery = false;
  bool _isUploading = false;
  String? _errorMessage;

  /// Prevents infinite re-init loops on flaky CameraX devices.
  DateTime? _lastCameraRecoveryAt;
  static const Duration _cameraRecoveryCooldown = Duration(seconds: 8);
  bool _isRecoveringCamera = false;
  Completer<void>? _cameraRecoveryCompleter;
  static const Duration _takePictureTimeout = Duration(seconds: 12);
  static const Duration _singleFrameStreamTimeout = Duration(seconds: 3);

  // Serializes camera operations (dispose/init/capture/stream) to avoid races on Android TV.
  Future<void> _cameraOp = Future<void>.value();
  int _cameraGeneration = 0;

  Future<T> _withCameraLock<T>(Future<T> Function() fn) {
    final next = Completer<void>();
    final prev = _cameraOp;
    _cameraOp = next.future;
    return prev
        .catchError((_) {})
        .then((_) => fn())
        .whenComplete(() => next.complete());
  }
  
  // Timer tracking for upload
  Timer? _uploadTimer;
  int _uploadElapsedSeconds = 0;
  
  // Countdown timer for capture
  int? _countdownValue;
  Timer? _countdownTimer;

  /// Zoom range and current value; null when zoom is not supported.
  double? _minZoom;
  double? _maxZoom;
  double _currentZoom = 1.0;
  static const _zoomLoadTimeout = Duration(seconds: 3);

  /// Max wait for camera enumeration. On devices with only external cameras, CameraX
  /// validation can retry for a long time; we timeout so the UI stays responsive.
  static const _loadCamerasTimeout = Duration(seconds: 25);

  /// Camera preview rotation in degrees (0, 90, 180, 270). Persisted in SharedPreferences.
  int _previewRotationDegrees = AppConstants.kCameraPreviewRotationDefault;
  bool _isPreviewRotationConfiguredByUser = false;

  /// Display rotation from Android WindowManager (0–3: ROTATION_0, 90, 180, 270). Used for preview correction and capture lock.
  int _displayRotation = 0;

  CaptureViewModel({
    ApiService? apiService,
    SessionManager? sessionManager,
  })  : _apiService = apiService ?? ApiService(),
        _sessionManager = sessionManager ?? SessionManager();

  CameraController? get cameraController => _cameraController;
  PhotoModel? get capturedPhoto => _capturedPhoto;
  Size? get capturedImagePixelSize => _capturedImagePixelSize;
  double? get lockedCaptureCardAspectRatio => _lockedCaptureCardAspectRatio;

  set capturedPhoto(PhotoModel? photo) {
    _capturedPhoto = photo;
    _capturedImagePixelSize = null;
    if (photo != null) {
      unawaited(_refreshCapturedImagePixelSize(photo.imageFile));
    }
    notifyListeners();
  }
  List<CameraDescription> get availableCameras => _availableCameras;
  CameraDescription? get currentCamera => _currentCamera;
  bool get isLoadingCameras => _isLoadingCameras;
  bool get isInitializing => _isInitializing;
  bool get isCapturing => _isCapturing;
  bool get isSelectingFromGallery => _isSelectingFromGallery;
  bool get isUploading => _isUploading;
  int get uploadElapsedSeconds => _uploadElapsedSeconds;
  String? get errorMessage => _errorMessage;
  bool get hasError => _errorMessage != null;
  int? get countdownValue => _countdownValue;
  bool get isCountingDown => _countdownValue != null;
  int get previewRotationDegrees => _previewRotationDegrees;
  bool get shouldUseLandscapePreviewRotationWorkaround =>
      _deviceType == AppDeviceType.androidTv ||
      _deviceType == AppDeviceType.androidTablet;
  double? get minZoom => _minZoom;
  double? get maxZoom => _maxZoom;
  double get currentZoom => _currentZoom;
  /// True when device supports zoom (min and max available and max > min).
  bool get hasZoomSupport =>
      _minZoom != null &&
      _maxZoom != null &&
      _maxZoom! > _minZoom!;

  /// Display rotation from device (0–3). Used for preview orientation correction (Android).
  int get displayRotation => _displayRotation;

  /// Increments to force preview subtree remounts (useful on web where platform views can be sticky).
  int get previewNonce => _previewNonce;
  int _previewNonce = 0;

  /// Listener for controller updates (aligned with camera package example).
  void _onCameraControllerUpdate() {
    final ctrl = _cameraController;
    if (ctrl == null) return;
    if (ctrl.value.hasError) {
      final desc = ctrl.value.errorDescription;
      _errorMessage = desc;
      // CameraX can emit recoverable errors asynchronously (not always through takePicture()).
      // If we see that state, attempt a controlled re-init so capture can succeed.
      // IMPORTANT: do not dispose/re-init while a capture or stream fallback is running.
      if (!_isCapturing &&
          !_shouldUseStreamOnlyCapture() &&
          desc != null &&
          _looksLikeCameraXRecoverableError(desc)) {
        unawaited(_recoverCamera(reason: 'controller.hasError(recoverable)', details: desc));
      }
    }
    notifyListeners();
  }

  bool _shouldUseStreamOnlyCapture() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    final camera = _currentCamera;
    if (camera == null) return false;
    final isExternal = camera.lensDirection == CameraLensDirection.external ||
        _looksLikeExternalCameraName(camera.name);
    return isExternal || _deviceType == AppDeviceType.androidTv;
  }

  bool _looksLikeCameraXRecoverableError(String message) {
    final m = message.toLowerCase();
    return m.contains('recoverable error') ||
        m.contains('otherrecoverableerror') ||
        m.contains('will attempt to recover') ||
        m.contains('camera device has encountered a recoverable error');
  }

  /// Resolution preset currently in use (after init). Null if camera not initialized.
  ResolutionPreset? get effectiveResolutionPreset =>
      _cameraController?.resolutionPreset;

  /// Actual preview size in use (from controller after init). Null until camera is initialized.
  /// Use this to show or log the resolution the camera is actually using.
  Size? get previewSize => _cameraController?.value.previewSize;

  /// Same math as the capture screen’s live preview display size (after auto + manual rotation).
  Size? get previewDisplaySizeForCard {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return null;
    }

    final previewSize = controller.value.previewSize;
    final baseAspectRatio = controller.value.aspectRatio;
    final autoQuarterTurns = _androidTvPreviewQuarterTurns();
    final manualQuarterTurns = (_previewRotationDegrees ~/ 90) % 4;
    final effectiveQuarterTurns =
        (autoQuarterTurns + manualQuarterTurns) % 4;

    final displayAspectRatio =
        effectiveQuarterTurns.isOdd ? 1 / baseAspectRatio : baseAspectRatio;
    final (width, height) = _previewDisplayDimensions(
      previewSize: previewSize,
      effectiveQuarterTurns: effectiveQuarterTurns,
      displayAspectRatio: displayAspectRatio,
    );

    if (width <= 0 || height <= 0) return null;
    return Size(width, height);
  }

  /// Android TV / external camera preview correction in 90° steps.
  int get previewAutoQuarterTurns => _androidTvPreviewQuarterTurns();

  int _androidTvPreviewQuarterTurns() {
    final camera = _currentCamera;
    if (camera == null) return 0;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return 0;
    if (!shouldUseLandscapePreviewRotationWorkaround &&
        camera.lensDirection != CameraLensDirection.external) {
      return 0;
    }

    final surfaceRotationDegrees = switch (_displayRotation) {
      1 => 90,
      2 => 180,
      3 => 270,
      _ => 0,
    };

    final sensorOrientation = camera.sensorOrientation % 360;
    final rotationDegrees = switch (camera.lensDirection) {
      CameraLensDirection.front =>
        (sensorOrientation + surfaceRotationDegrees) % 360,
      _ => (sensorOrientation - surfaceRotationDegrees + 360) % 360,
    };

    return ((360 - rotationDegrees) % 360) ~/ 90;
  }

  void _snapshotLockedCaptureCardAspectFromLivePreview() {
    final d = previewDisplaySizeForCard;
    if (d != null && d.height > 0) {
      _lockedCaptureCardAspectRatio =
          (d.width / d.height).clamp(0.35, 2.85);
    }
  }

  /// Native camera characteristics (Android Camera2; default/placeholder on iOS/Web). Fetched after camera init.
  CameraDetails? _nativeCameraDetails;
  CameraDetails? get nativeCameraDetails => _nativeCameraDetails;

  /// Fetches display rotation from Android WindowManager (0–3). Returns 0 on non-Android or on error.
  Future<int> _fetchDisplayRotation() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return 0;
    try {
      final result = await const MethodChannel('photobooth/display').invokeMethod<int>('getRotation');
      return result ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Refresh display rotation (0–3) after orientation changes (Android).
  Future<void> refreshDisplayRotation() async {
    final r = await _fetchDisplayRotation();
    if (r == _displayRotation) return;
    _displayRotation = r;
    unawaited(_applyDefaultPreviewRotationForDevice());
    notifyListeners();
  }

  /// Loads saved preview rotation from preferences (call when screen opens).
  Future<void> loadPreviewRotation() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final migrationVersion = prefs.getInt(
            AppConstants.kCameraPreviewRotationMigrationVersionKey,
          ) ??
          0;
      final saved = prefs.getInt(AppConstants.kCameraPreviewRotationKey);
      final isConfigured =
          prefs.getBool(AppConstants.kCameraPreviewRotationConfiguredKey) ??
              false;
      final needsRotationReset =
          migrationVersion < AppConstants.kCameraPreviewRotationMigrationVersion;

      if (needsRotationReset) {
        _isPreviewRotationConfiguredByUser = false;
        _previewRotationDegrees = AppConstants.kCameraPreviewRotationDefault;
        await prefs.setInt(
          AppConstants.kCameraPreviewRotationKey,
          AppConstants.kCameraPreviewRotationDefault,
        );
        await prefs.setBool(
          AppConstants.kCameraPreviewRotationConfiguredKey,
          false,
        );
        await prefs.setInt(
          AppConstants.kCameraPreviewRotationMigrationVersionKey,
          AppConstants.kCameraPreviewRotationMigrationVersion,
        );
      } else
      if (saved != null &&
          [0, 90, 180, 270].contains(saved) &&
          isConfigured) {
        _isPreviewRotationConfiguredByUser = true;
        _previewRotationDegrees = saved;
      } else if (saved != null && [0, 90, 180, 270].contains(saved)) {
        // Older builds persisted a default rotation even though it was not
        // applied to the preview. Reset that legacy value to a neutral default.
        _isPreviewRotationConfiguredByUser = false;
        _previewRotationDegrees = AppConstants.kCameraPreviewRotationDefault;
        await prefs.setInt(
          AppConstants.kCameraPreviewRotationKey,
          AppConstants.kCameraPreviewRotationDefault,
        );
        await prefs.setInt(
          AppConstants.kCameraPreviewRotationMigrationVersionKey,
          AppConstants.kCameraPreviewRotationMigrationVersion,
        );
      } else {
        _isPreviewRotationConfiguredByUser = false;
        _previewRotationDegrees = AppConstants.kCameraPreviewRotationDefault;
        await prefs.setInt(
          AppConstants.kCameraPreviewRotationKey,
          AppConstants.kCameraPreviewRotationDefault,
        );
        await prefs.setInt(
          AppConstants.kCameraPreviewRotationMigrationVersionKey,
          AppConstants.kCameraPreviewRotationMigrationVersion,
        );
      }
      notifyListeners();
    } catch (e, st) {
      AppLogger.error(
        'Failed to load preview rotation; using defaults',
        error: e,
        stackTrace: st,
      );
      await ErrorReportingManager.recordError(
        e,
        st,
        reason: 'loadPreviewRotation failed',
        extraInfo: {
          'defaultRotation': AppConstants.kCameraPreviewRotationDefault,
        },
        fatal: false,
      );
    }
  }

  /// Saves and applies preview rotation (0, 90, 180, 270). Persists across sessions.
  Future<void> setPreviewRotation(int degrees) async {
    if (![0, 90, 180, 270].contains(degrees)) return;
    _isPreviewRotationConfiguredByUser = true;
    _previewRotationDegrees = degrees;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(AppConstants.kCameraPreviewRotationKey, degrees);
      await prefs.setBool(
        AppConstants.kCameraPreviewRotationConfiguredKey,
        true,
      );
    } catch (e, st) {
      AppLogger.error(
        'Failed to persist preview rotation',
        error: e,
        stackTrace: st,
      );
      await ErrorReportingManager.recordError(
        e,
        st,
        reason: 'setPreviewRotation failed',
        extraInfo: {'degrees': degrees},
        fatal: false,
      );
    }
    notifyListeners();
  }

  void _startUploadTimer() {
    _uploadElapsedSeconds = 0;
    _uploadTimer?.cancel();
    _uploadTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _uploadElapsedSeconds++;
      notifyListeners();
    });
  }

  void _stopUploadTimer() {
    _uploadTimer?.cancel();
    _uploadTimer = null;
  }
  bool get isReady {
    return _cameraController != null &&
        _cameraController!.value.isInitialized;
  }

  /// Display name for a camera (Back, Front, External, etc.).
  String getCameraDisplayName(CameraDescription camera) {
    if (camera.lensDirection == CameraLensDirection.back) return 'Back Camera';
    if (camera.lensDirection == CameraLensDirection.front) return 'Front Camera';
    if (camera.lensDirection == CameraLensDirection.external) {
      if (camera.name.contains(':')) {
        final deviceId = camera.name.split(':').last.split(',').first;
        return 'External Camera $deviceId';
      }
      return 'External Camera';
    }
    if (camera.name.contains(':')) {
      final deviceId = camera.name.split(':').last.split(',').first;
      return 'Camera $deviceId';
    }
    return 'Camera';
  }

  /// Picks the default camera: prefer real external (HDMI/USB), then built-in **front** when
  /// both front and back exist (kiosk selfie tablets), else back, else first.
  /// On iPad the plugin can misreport built-in as external, so we prefer by name (UUID) first.
  CameraDescription _pickDefaultCamera(List<CameraDescription> cameras) {
    if (cameras.isEmpty) {
      throw StateError('No cameras available');
    }
    // 1) Prefer by name (UUID = real external on iOS; avoids mislabeled built-in)
    final byName = cameras.where((c) => _looksLikeExternalCameraName(c.name)).toList();
    if (byName.isNotEmpty) {
      return byName.first;
    }
    // 2) Then by lensDirection.external (HDMI capture card, USB webcam, etc.)
    final byDirection = cameras.where(
      (c) => c.lensDirection == CameraLensDirection.external,
    ).toList();
    if (byDirection.isNotEmpty) {
      return byDirection.first;
    }
    // 3) Built-in only: prefer front when both front and back exist (kiosk / tablet selfie)
    final fronts = cameras
        .where((c) => c.lensDirection == CameraLensDirection.front)
        .toList();
    final backs =
        cameras.where((c) => c.lensDirection == CameraLensDirection.back).toList();
    if (fronts.isNotEmpty && backs.isNotEmpty) {
      return fronts.first;
    }
    if (fronts.isNotEmpty) return fronts.first;
    if (backs.isNotEmpty) return backs.first;
    return cameras.first;
  }

  /// True if camera name looks like a real external device (e.g. iOS UUID).
  /// Excludes built-in cameras whose names contain "built-in" (plugin can misreport direction).
  bool _looksLikeExternalCameraName(String name) =>
      looksLikeExternalCameraName(name);

  /// Set device type from UI (from [DeviceClassifier.getDeviceType]).
  /// Used to filter cameras: tablet/TV → external only, phone → built-in only.
  void setDeviceType(AppDeviceType? type) {
    _deviceType = type;
    unawaited(_applyDefaultPreviewRotationForDevice());
  }

  Future<void> _applyDefaultPreviewRotationForDevice() async {
    if (_isPreviewRotationConfiguredByUser) return;
    if (!shouldUseLandscapePreviewRotationWorkaround) return;

    // Android TV devices often report ROTATION_0 even though the physical display
    // is landscape. Tablets generally report real rotation and should follow the
    // device orientation (no forced default rotation).
    final desiredRotation =
        _deviceType == AppDeviceType.androidTv && _displayRotation == 0
            ? 270
            : AppConstants.kCameraPreviewRotationDefault;
    if (_previewRotationDegrees == desiredRotation) return;

    _previewRotationDegrees = desiredRotation;
    notifyListeners();
  }

  /// Sorts cameras so external ones come first (for default selection and list order).
  List<CameraDescription> _externalCamerasFirst(List<CameraDescription> cameras) {
    if (cameras.length <= 1) return cameras;
    final list = List<CameraDescription>.from(cameras);
    list.sort((a, b) {
      final aExt = a.lensDirection == CameraLensDirection.external || _looksLikeExternalCameraName(a.name);
      final bExt = b.lensDirection == CameraLensDirection.external || _looksLikeExternalCameraName(b.name);
      if (aExt == bExt) return 0;
      return aExt ? -1 : 1;
    });
    return list;
  }

  void _applyCachedCameraList() {
    if (_cachedAvailableCameras == null) return;
    _availableCameras = _externalCamerasFirst(_cachedAvailableCameras!);
    if (_currentCamera == null && _availableCameras.isNotEmpty) {
      _currentCamera = _pickDefaultCamera(_availableCameras);
    }
  }

  Future<bool> _ensureAndroidCameraPermission() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return true;
    }
    final status = await Permission.camera.status;
    if (status.isGranted) return true;
    AppLogger.debug('📷 Camera permission not granted, requesting...');
    final result = await Permission.camera.request();
    AppLogger.debug('📷 Permission result: $result');
    if (result.isGranted) return true;
    _errorMessage = 'Camera permission is required to detect and use cameras.';
    return false;
  }

  Future<void> _reportEmptyCameraEnumeration() async {
    ErrorReportingManager.log('❌ Camera enumeration returned 0 cameras');
    await ErrorReportingManager.recordError(
      Exception('Camera enumeration returned 0 cameras'),
      StackTrace.current,
      reason: 'No cameras detected',
      extraInfo: {
        'platform': defaultTargetPlatform.name,
        'message':
            'availableCameras() returned empty list; no exception thrown',
      },
      fatal: false,
    );
  }

  void _assignEnumeratedCameras(List<CameraDescription> allCameras) {
    if (allCameras.isEmpty) {
      unawaited(_reportEmptyCameraEnumeration());
    }
    AppLogger.debug('📷 Detected ${allCameras.length} camera(s):');
    for (final c in allCameras) {
      AppLogger.debug('  - Name: "${c.name}", Direction: ${c.lensDirection}');
    }
    _availableCameras = _externalCamerasFirst(allCameras);
    _cachedAvailableCameras = List<CameraDescription>.from(allCameras);
    AppLogger.debug(
      '📋 CaptureViewModel.loadCameras - Device: $_deviceType, '
      'showing ${_availableCameras.length} camera(s):',
    );
    for (var i = 0; i < _availableCameras.length; i++) {
      final c = _availableCameras[i];
      AppLogger.debug(
        '   ${i + 1}. ${cameraDescriptionLabel(c)} (${c.lensDirection})',
      );
    }
    if (_currentCamera == null && _availableCameras.isNotEmpty) {
      _currentCamera = _pickDefaultCamera(_availableCameras);
      AppLogger.debug(
        '📷 Auto-selected camera: ${cameraDescriptionLabel(_currentCamera!)}',
      );
    }
  }

  /// Loads available cameras when user opens Capture screen.
  Future<void> loadCameras({bool forceRefresh = false}) async {
    _isLoadingCameras = true;
    _errorMessage = null;
    notifyListeners();

    try {
      if (!forceRefresh && _cachedAvailableCameras != null) {
        _applyCachedCameraList();
        notifyListeners();
        return;
      }

      if (!await _ensureAndroidCameraPermission()) {
        return;
      }

      final allCameras = await cam.availableCameras().timeout(
        _loadCamerasTimeout,
        onTimeout: () => throw TimeoutException(
          'Camera enumeration timed out after ${_loadCamerasTimeout.inSeconds}s',
        ),
      );

      _assignEnumeratedCameras(allCameras);
      notifyListeners();
    } on TimeoutException {
      _errorMessage = 'Camera took too long to load. Please try again.';
      ErrorReportingManager.log('❌ Camera enumeration timed out');
    } catch (e, stackTrace) {
      _errorMessage = 'Failed to load cameras: $e';
      await ErrorReportingManager.recordError(
        e,
        stackTrace,
        reason: 'loadCameras failed',
        extraInfo: {'error': e.toString(), 'errorType': e.runtimeType.toString()},
        fatal: false,
      );
      notifyListeners();
    } finally {
      _isLoadingCameras = false;
      notifyListeners();
    }
  }

  /// Resets the camera screen and initializes with the first available camera
  /// This is a common function used both when entering the screen and when reloading
  Future<void> resetAndInitializeCameras({bool forceRefresh = false}) async {
    AppLogger.debug('🔄 Resetting camera screen and initializing cameras...');
    
    // CRITICAL: Prevent reset while capture is in progress
    if (_isCapturing) {
      AppLogger.debug('⚠️ Cannot reset cameras - capture in progress');
      ErrorReportingManager.log('⚠️ Reset blocked - capture in progress');
      return;
    }

    // Clear any captured photo
    _capturedPhoto = null;
    _capturedImagePixelSize = null;
    _lockedCaptureCardAspectRatio = null;
    
    // Dispose current camera controller
    if (_cameraController != null) {
      AppLogger.debug('   Disposing current camera controller...');
      try {
        _cameraController!.removeListener(_onCameraControllerUpdate);
        await _cameraController!.dispose();
      } catch (e, stackTrace) {
        AppLogger.debug('   ⚠️ Warning: Error disposing camera: $e');
        ErrorReportingManager.log('⚠️ Warning: Error disposing camera controller');
        await ErrorReportingManager.recordError(
          e,
          stackTrace,
          reason: 'Error disposing camera controller during reset',
          extraInfo: {'error': e.toString()},
          fatal: false,
        );
      }
      _cameraController = null;
    }

    // Clear current camera selection
    _currentCamera = null;
    
    // Clear any previous errors
    _errorMessage = null;
    
    const initTimeout = Duration(seconds: 25);
    try {
      await (() async {
        await loadCameras(forceRefresh: forceRefresh);
        if (_availableCameras.isNotEmpty) {
          _currentCamera = _pickDefaultCamera(_availableCameras);
          AppLogger.debug(
            '📷 Selected camera: ${cameraDescriptionLabel(_currentCamera!)}',
          );
          await initializeCamera(_currentCamera!);
        } else {
          AppLogger.debug('⚠️ No cameras available');
          _errorMessage = 'No cameras available';
          notifyListeners();
        }
      })().timeout(initTimeout);
    } on TimeoutException catch (_) {
      AppLogger.debug('⏱️ Camera initialization timed out after ${initTimeout.inSeconds}s');
      _errorMessage = 'Camera took too long to start. Please try again.';
      _isInitializing = false;
      notifyListeners();
    }
  }

  /// Reloads cameras and selects the first one, then reinitializes
  /// @deprecated Use resetAndInitializeCameras() instead
  Future<void> reloadAndSelectFirstCamera() async {
    await resetAndInitializeCameras();
  }

  /// Switches to a different camera
  Future<void> switchCamera(CameraDescription camera) async {
    if (_isCapturing) {
      AppLogger.debug('⚠️ Cannot switch cameras - capture in progress');
      ErrorReportingManager.log('⚠️ Camera switch blocked - capture in progress');
      return;
    }
    if (_currentCamera?.name == camera.name) {
      AppLogger.debug('⚠️ Already using camera: ${camera.name}');
      return;
    }

    AppLogger.debug('🔄 Switching camera to: ${camera.name} (${camera.lensDirection})');

    _currentCamera = camera;
    await initializeCamera(camera);
  }

  CameraDescription _resolveListedCamera(CameraDescription camera) {
    try {
      return _availableCameras.firstWhere((c) => c.name == camera.name);
    } catch (_) {
      return camera;
    }
  }

  Future<bool> _tryFastCameraDescriptionSwitch(
    CameraDescription cameraToUse,
    CameraDescription camera,
  ) async {
    final ctrl = _cameraController;
    if (ctrl == null || !ctrl.value.isInitialized) return false;
    try {
      await ctrl.setDescription(cameraToUse);
      _currentCamera = camera;
      _isInitializing = false;
      _errorMessage = null;
      notifyListeners();
      unawaited(_finishCameraSetup(camera));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _disposeCameraControllerForSwitch() async {
    final hadController = _cameraController != null;
    if (_cameraController == null) return;
    AppLogger.debug('🔄 Disposing existing camera controller before switch...');
    try {
      _cameraController!.removeListener(_onCameraControllerUpdate);
      await _cameraController!.dispose();
    } catch (e) {
      AppLogger.debug('   ⚠️ Warning: Error disposing existing controller: $e');
    }
    _cameraController = null;
    _cameraGeneration++;
    if (hadController) {
      await Future.delayed(
        Duration(milliseconds: AppConstants.kCameraDisposeToReopenDelayMs),
      );
    }
  }

  void _logCameraInitializationStart(CameraDescription camera) {
    AppLogger.debug('📸 CaptureViewModel.initializeCamera called:');
    AppLogger.debug('   Camera name: ${camera.name}');
    AppLogger.debug('   Camera direction: ${camera.lensDirection}');
    AppLogger.debug('   Camera sensor orientation: ${camera.sensorOrientation}');
    unawaited(ErrorReportingManager.setCameraContext(
      cameraId: camera.name,
      cameraDirection: camera.lensDirection.toString(),
      isExternal: camera.lensDirection == CameraLensDirection.external,
    ));
    ErrorReportingManager.log('Initializing camera: ${camera.name}');
  }

  Future<void> _openFreshCameraController(
    CameraDescription cameraToUse,
    CameraDescription camera,
  ) async {
    final isExternal = isExternalCaptureCamera(
      camera,
      _looksLikeExternalCameraName,
    );
    final preset = captureResolutionPreset(
      deviceType: _deviceType,
      isExternal: isExternal,
    );
    final streamFormat = captureStreamFormat(
      deviceType: _deviceType,
      isExternal: isExternal,
    );
    _cameraController = CameraController(
      cameraToUse,
      preset,
      enableAudio: false,
      imageFormatGroup: streamFormat,
    );
    _cameraController!.addListener(_onCameraControllerUpdate);
    await _cameraController!.initialize().timeout(
      const Duration(seconds: 15),
      onTimeout: () => throw Exception(
        'Camera initialization timed out after 15 seconds',
      ),
    );

    final ctrl = _cameraController;
    if (ctrl == null || !ctrl.value.isInitialized) {
      _errorMessage = 'Camera controller is null after initialization';
      return;
    }

    final size = ctrl.value.previewSize;
    AppLogger.debug('✅ CaptureViewModel - Camera initialized with ${preset.name}:');
    AppLogger.debug('   Active camera: ${ctrl.description.name}');
    AppLogger.debug(
      '   Preview size: ${size?.width ?? "?"}x${size?.height ?? "?"}',
    );
    _currentCamera = camera;
    _minZoom = null;
    _maxZoom = null;
    _currentZoom = 1.0;
    _errorMessage = null;
    unawaited(_finishCameraSetup(camera));
  }

  Future<void> _handleCameraInitializationError(
    Object e,
    StackTrace stackTrace,
    CameraDescription camera,
  ) async {
    if (e is app_exceptions.PermissionException) {
      _errorMessage = e.message;
      ErrorReportingManager.log(
        '❌ Permission exception during camera initialization',
      );
      await ErrorReportingManager.recordError(
        e,
        stackTrace,
        reason: 'Permission exception',
        extraInfo: {'message': e.message, 'camera_name': camera.name},
      );
      return;
    }
    if (e is app_exceptions.CameraException) {
      _errorMessage = e.message;
      ErrorReportingManager.log('❌ Camera exception during initialization');
      await ErrorReportingManager.recordError(
        e,
        stackTrace,
        reason: 'Camera exception',
        extraInfo: {
          'message': e.message,
          'camera_name': camera.name,
          'camera_direction': camera.lensDirection.toString(),
        },
      );
      return;
    }
    _errorMessage = 'Failed to initialize camera: $e';
    ErrorReportingManager.log('❌ Unexpected error during camera initialization');
    await ErrorReportingManager.recordError(
      e,
      stackTrace,
      reason: 'Unexpected camera initialization error',
      extraInfo: {'error': e.toString(), 'camera_name': camera.name},
    );
  }

  /// Initializes the camera with the selected camera
  Future<void> initializeCamera(CameraDescription camera) async {
    await _withCameraLock(() async {
      _isInitializing = true;
      _errorMessage = null;
      notifyListeners();

      try {
        _minZoom = null;
        _maxZoom = null;
        _currentZoom = 1.0;

        final cameraToUse = _resolveListedCamera(camera);
        if (await _tryFastCameraDescriptionSwitch(cameraToUse, camera)) {
          return;
        }

        await _disposeCameraControllerForSwitch();
        _logCameraInitializationStart(camera);
        await _openFreshCameraController(cameraToUse, camera);
      } catch (e, stackTrace) {
        await _handleCameraInitializationError(e, stackTrace, camera);
      } finally {
        _isInitializing = false;
        notifyListeners();
      }
    });
  }

  Future<void> _finishCameraSetup(CameraDescription camera) async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;

    try {
      final rotation = await _fetchDisplayRotation();
      _displayRotation = rotation;
      AppLogger.debug('   Display rotation: $rotation');

      // Best-effort capture lock for cameras that report 0/180 sensor orientation.
      // Skip for external/UVC (HDMI capture cards): locking can distort or break still JPEGs.
      final isExternal = camera.lensDirection == CameraLensDirection.external ||
          _looksLikeExternalCameraName(camera.name);
      if (!isExternal &&
          !kIsWeb &&
          defaultTargetPlatform == TargetPlatform.android &&
          rotation == 1) {
        final so = camera.sensorOrientation;
        if (so == 0 || so == 180) {
          try {
            await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
          } on CameraException {
            // Best-effort
          }
        }
      }

      await _applyDefaultPreviewRotationForDevice();
      notifyListeners();
    } catch (_) {
      // Preview can still work without this metadata.
    }

    await _loadZoomInBackground();

    // Fetch native camera details (Android: Camera2; iOS/Web: default values).
    try {
      final details = await CameraNativeDetails.getCameraDetails(camera.name);
      _nativeCameraDetails = details;
      if (details != null) {
        AppLogger.debug('   Native camera details (${details.platform}):');
        AppLogger.debug('     activeArray: ${details.activeArrayWidth}x${details.activeArrayHeight}');
        AppLogger.debug('     zoomRatioRange: ${details.zoomRatioRangeMin}..${details.zoomRatioRangeMax}');
        AppLogger.debug('     maxDigitalZoom: ${details.maxDigitalZoom}');
        AppLogger.debug('     lensFacing: ${details.lensFacing}');
        if (details.supportedPreviewSizes.isNotEmpty) {
          AppLogger.debug('     previewSizes: ${details.supportedPreviewSizes.take(5).join(", ")}${details.supportedPreviewSizes.length > 5 ? "..." : ""}');
        }
      }
    } catch (_) {
      _nativeCameraDetails = null;
    }
    notifyListeners();
  }

  /// Loads zoom range in background with timeout so init never hangs.
  Future<void> _loadZoomInBackground() async {
    final ctrl = _cameraController;
    if (ctrl == null || !ctrl.value.isInitialized) return;

    // camera_web only supports zoom when the track exposes `zoom` in
    // getCapabilities(); otherwise getMin/getMax/setZoom throw and emit
    // camera errors ("zoom level is not supported by the current camera").
    // Skip zoom APIs on web so preview/capture work without noisy failures.
    if (kIsWeb) {
      _minZoom = null;
      _maxZoom = null;
      _currentZoom = 1.0;
      notifyListeners();
      return;
    }

    double? minZ;
    double? maxZ;
    try {
      minZ = await ctrl.getMinZoomLevel().timeout(
        _zoomLoadTimeout,
        onTimeout: () => throw TimeoutException('getMinZoomLevel'),
      );
      maxZ = await ctrl.getMaxZoomLevel().timeout(
        _zoomLoadTimeout,
        onTimeout: () => throw TimeoutException('getMaxZoomLevel'),
      );
      // Keep preview at minimum zoom (no zoom buttons in UI).
      await ctrl.setZoomLevel(minZ);
    } on CameraException {
      // Zoom not supported
    } on TimeoutException {
      AppLogger.debug('Zoom level load timed out');
    } catch (e, st) {
      AppLogger.error('Zoom load failed', error: e, stackTrace: st);
      await ErrorReportingManager.recordError(
        e,
        st,
        reason: 'loadZoomInBackground failed',
        fatal: false,
      );
    }
    _minZoom = minZ;
    _maxZoom = maxZ;
    if (minZ != null && maxZ != null) {
      _currentZoom = minZ;
    } else {
      _currentZoom = 1.0;
    }
    notifyListeners();
  }

  /// Sets zoom level (clamped to device min/max). No-op if zoom not supported.
  Future<void> setZoomLevel(double level) async {
    final ctrl = _cameraController;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    final min = _minZoom;
    final max = _maxZoom;
    if (min == null || max == null) return;
    final clamped = level.clamp(min, max);
    try {
      await ctrl.setZoomLevel(clamped);
      _currentZoom = clamped;
      notifyListeners();
    } on CameraException catch (e) {
      AppLogger.debug('setZoomLevel failed: $e');
    }
  }

  /// Starts a countdown and then captures a photo
  /// Countdown duration is configured via AppConstants.kCaptureCountdownSeconds
  Future<void> capturePhotoWithCountdown() async {
    if (!isReady || _isCapturing || _countdownValue != null) {
      return;
    }
    
    AppLogger.debug('📸 Starting capture countdown (${AppConstants.kCaptureCountdownSeconds}s)...');
    
    // Start countdown from configured value
    _countdownValue = AppConstants.kCaptureCountdownSeconds;
    notifyListeners();
    
    // Countdown 3 -> 2 -> 1 -> capture
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (_countdownValue == null) {
        timer.cancel();
        if (identical(_countdownTimer, timer)) {
          _countdownTimer = null;
        }
        return;
      }
      
      if (_countdownValue! > 1) {
        _countdownValue = _countdownValue! - 1;
        notifyListeners();
      } else {
        // Countdown finished, capture the photo
        timer.cancel();
        if (identical(_countdownTimer, timer)) {
          _countdownTimer = null;
        }
        _countdownValue = null;
        notifyListeners();
        
        // Small delay to ensure UI updates before capture
        await Future.delayed(const Duration(milliseconds: 100));
        await capturePhoto();
      }
    });
  }
  
  /// Cancels the countdown if in progress
  void cancelCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _countdownValue = null;
    notifyListeners();
  }

  Future<bool> _guardCaptureReady() async {
    if (isReady) return true;
    var debugInfo = 'Camera not ready.\n\nDebug Info:\n';
    debugInfo += '- Controller Exists: ${_cameraController != null}\n';
    if (_cameraController != null) {
      debugInfo +=
          '- Controller Initialized: ${_cameraController!.value.isInitialized}\n';
    }
    _errorMessage = debugInfo;
    ErrorReportingManager.log('❌ Camera not ready for capture');
    await ErrorReportingManager.recordError(
      Exception('Camera not ready for photo capture'),
      StackTrace.current,
      reason: 'Camera not ready',
      extraInfo: {'debug_info': debugInfo},
    );
    notifyListeners();
    return false;
  }

  Future<XFile> _obtainRawCaptureFile() async {
    if (_shouldUseStreamOnlyCapture()) {
      WebFlowTrace.log('CAPTURE', 'streamFallback_start');
      final file = await _captureSingleFrameFallback(
        reason: 'streamOnlyCapture',
        details:
            'android=${_deviceType?.toString()} camera=${_currentCamera?.name ?? "unknown"}',
      );
      WebFlowTrace.log('CAPTURE', 'streamFallback_done pathLen=${file.path.length}');
      return file;
    }
    try {
      WebFlowTrace.log('CAPTURE', 'takePicture_start');
      final file = await _takePictureWithRecovery();
      WebFlowTrace.log('CAPTURE', 'takePicture_done pathLen=${file.path.length}');
      return file;
    } on TimeoutException catch (e) {
      return _captureSingleFrameFallback(
        reason: AppStrings.takePictureTimeout,
        details: e.toString(),
      );
    } on CameraException catch (e) {
      return _captureSingleFrameFallback(
        reason: 'takePicture CameraException',
        details: e.toString(),
      );
    }
  }

  Future<void> _assignCapturedPhotoModel(XFile savedFile) async {
    final cameraId =
        _cameraController?.description.name ?? _currentCamera?.name;
    final photoId = _uuid.v4();
    _snapshotLockedCaptureCardAspectFromLivePreview();
    _capturedPhoto = PhotoModel(
      id: photoId,
      imageFile: savedFile,
      capturedAt: DateTime.now(),
      cameraId: cameraId,
    );
    _capturedImagePixelSize = null;
    unawaited(_refreshCapturedImagePixelSizeSoon(savedFile));
    unawaited(ErrorReportingManager.setPhotoCaptureContext(
      photoId: photoId,
      sessionId: _sessionManager.sessionId,
    ));
    ErrorReportingManager.log('Photo captured successfully: $photoId');
    WebFlowTrace.log('CAPTURE', 'photoModel_set photoId=$photoId');
    notifyListeners();
  }

  Future<void> _handleCaptureCameraException(
    CameraException e,
    StackTrace stackTrace,
  ) async {
    WebFlowTrace.log('CAPTURE', 'ERROR CameraException $e');
    final errorString = e.toString();
    final isCameraClosedError = errorString.contains('Camera is closed') ||
        errorString.contains('camera is closed') ||
        errorString.contains('CameraDeviceImpl.close');
    await ErrorReportingManager.recordError(
      e,
      stackTrace,
      reason: isCameraClosedError
          ? 'Camera was closed during capture (race condition)'
          : 'CameraController takePicture failed',
      extraInfo: {
        'error': errorString,
        'camera': _currentCamera?.name ?? 'unknown',
      },
      fatal: false,
    );
    _errorMessage = 'Camera Error:\n$e';
    notifyListeners();
  }

  Future<void> _handleCaptureGenericError(
    Object e,
    StackTrace stackTrace,
  ) async {
    WebFlowTrace.log('CAPTURE', 'ERROR $e');
    final isTimeout = e.toString().contains('TimeoutException') ||
        e.toString().contains('timed out') ||
        e.toString().contains('CAPTURE_TIMEOUT');
    _errorMessage = 'Capture Failed:\n$e';
    if (isTimeout) {
      await ErrorReportingManager.setCustomKeys({
        'timeout_occurred': true,
        'timeout_error': e.toString(),
      });
    }
    await ErrorReportingManager.recordError(
      e,
      stackTrace,
      reason: isTimeout ? 'Photo capture timeout' : 'Photo capture failed',
      extraInfo: {
        'error': e.toString(),
        'is_timeout': isTimeout,
        'camera': _currentCamera?.name ?? 'unknown',
      },
    );
    notifyListeners();
  }

  /// Captures a photo
  Future<void> capturePhoto() async {
    ErrorReportingManager.log('📸 Photo capture attempt started');
    unawaited(ErrorReportingManager.setCustomKeys({
      'capture_isReady': isReady,
      'capture_hasController': _cameraController != null,
      'capture_initialized': _cameraController?.value.isInitialized ?? false,
    }));

    if (!await _guardCaptureReady()) return;

    _isCapturing = true;
    _errorMessage = null;
    notifyListeners();

    try {
      WebFlowTrace.reset(label: 'capture');
      WebFlowTrace.log('CAPTURE', 'shutter_begin kIsWeb=$kIsWeb isReady=$isReady');
      final imageFile = await _obtainRawCaptureFile();
      final isFrontCamera =
          _currentCamera?.lensDirection == CameraLensDirection.front;
      WebFlowTrace.log('CAPTURE', 'normalize_start');
      final savedFile = await ImageHelper.normalizeAndSaveCapturedPhoto(
        imageFile,
        flipHorizontal: isFrontCamera,
      );
      WebFlowTrace.log('CAPTURE', 'normalize_done');
      await _assignCapturedPhotoModel(savedFile);
    } on CameraException catch (e, stackTrace) {
      await _handleCaptureCameraException(e, stackTrace);
    } catch (e, stackTrace) {
      await _handleCaptureGenericError(e, stackTrace);
    } finally {
      WebFlowTrace.log('CAPTURE', 'finally isCapturing=false');
      _isCapturing = false;
      notifyListeners();
    }
  }

  Future<XFile> _captureSingleFrameFallback({
    required String reason,
    required String details,
  }) async {
    return _withCameraLock(() async {
      final ctrl = _cameraController;
      final camera = _currentCamera;
      final isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
      final isExternal = camera?.lensDirection == CameraLensDirection.external ||
          (camera != null && _looksLikeExternalCameraName(camera.name));

      // Only use this fallback on Android external/TV where it is known to help.
      if (!isAndroid || camera == null || (!isExternal && _deviceType != AppDeviceType.androidTv)) {
        throw CameraException('captureFailed', 'Still capture failed ($reason): $details');
      }

      // Avoid fighting an in-progress recovery.
      final inFlightRecovery = _cameraRecoveryCompleter;
      if (inFlightRecovery != null) {
        try {
          await inFlightRecovery.future.timeout(const Duration(seconds: 4));
        } catch (_) {}
      }

      if (ctrl == null || !ctrl.value.isInitialized) {
        throw CameraException('cameraNotReady', 'Camera not initialized for fallback capture');
      }

      final gen = _cameraGeneration;

      ErrorReportingManager.log('🧯 Fallback capture: grabbing single streamed frame');
      await ErrorReportingManager.setCustomKeys({
        'camera_fallback_capture': true,
        'camera_fallback_reason': reason,
        'camera_fallback_details': details,
        'camera_fallback_camera': camera.name,
      });

      final completer = Completer<CameraImage>();
      bool streaming = false;
      try {
        streaming = true;
        await ctrl.startImageStream((CameraImage image) {
          if (completer.isCompleted) return;
          completer.complete(image);
        });
        final frame = await completer.future.timeout(_singleFrameStreamTimeout);

        // If camera was disposed/re-inited, abort to avoid calling stop on disposed controller.
        if (_cameraGeneration != gen || !identical(_cameraController, ctrl)) {
          throw CameraException('cameraRestarted', 'Camera restarted during fallback capture');
        }

        await ctrl.stopImageStream();
        streaming = false;

        final jpegBytes = await compute(cameraImageToJpegBytes, frame);
        final tempDir = await FileHelper.getTempDirectoryPath();
        const photosSubdir = 'photos';
        final photosDir = '$tempDir/$photosSubdir';
        await FileHelper.ensureDirectory(photosDir);
        final ts = DateTime.now().millisecondsSinceEpoch;
        final savePath = '$photosDir/streamcap_$ts.jpg';
        final file = FileHelper.createFile(savePath);
        await (file as dynamic).writeAsBytes(jpegBytes);
        return XFile((file as dynamic).path);
      } catch (e, st) {
        AppLogger.error('Fallback single-frame capture failed', error: e, stackTrace: st);
        await ErrorReportingManager.recordError(
          e,
          st,
          reason: 'fallback single-frame capture failed',
          extraInfo: {
            'fallback_reason': reason,
            'fallback_details': details,
            'camera': camera.name,
          },
          fatal: false,
        );
        rethrow;
      } finally {
        if (streaming) {
          // Only attempt stop if controller is still the same generation.
          if (identical(_cameraController, ctrl)) {
            try {
              await ctrl.stopImageStream();
            } catch (_) {}
          }
        }
      }
    });
  }

  Future<XFile> _takePictureWithRecovery() async {
    final ctrl = _cameraController;
    if (ctrl == null || !ctrl.value.isInitialized) {
      throw CameraException('cameraNotReady', 'Camera controller not initialized');
    }

    // If a recovery is already in progress (async CameraX error), wait briefly so we
    // don't start a capture against a closing camera.
    final inFlightRecovery = _cameraRecoveryCompleter;
    if (inFlightRecovery != null) {
      try {
        await inFlightRecovery.future.timeout(const Duration(seconds: 4));
      } catch (_) {
        // Best-effort; continue.
      }
    }

    // Attempt 1
    try {
      return await ctrl.takePicture().timeout(
        _takePictureTimeout,
        onTimeout: () => throw TimeoutException(AppStrings.takePictureTimeout),
      );
    } on CameraException catch (e) {
      // Attempt 2 (single recovery + retry) for known CameraX flaky states.
      final msg = e.toString().toLowerCase();
      final bool looksRecoverable =
          msg.contains('recoverable') ||
          msg.contains('otherrecoverableerror') ||
          msg.contains('camera is closed') ||
          msg.contains('cameradeviceimpl.close') ||
          msg.contains('camera2') ||
          msg.contains('capture failed');

      if (!looksRecoverable) rethrow;
      if (_isCapturing == false) {
        // capturePhoto() sets _isCapturing true before calling; if not, don’t recover here.
        rethrow;
      }

      final now = DateTime.now();
      final last = _lastCameraRecoveryAt;
      if (last != null && now.difference(last) < _cameraRecoveryCooldown) {
        rethrow;
      }
      _lastCameraRecoveryAt = now;

      final camera = _currentCamera;
      if (camera == null) rethrow;

      ErrorReportingManager.log('🔁 CameraX recoverable error; re-initializing camera and retrying takePicture');
      await ErrorReportingManager.setCustomKeys({
        'camera_recovery_attempted': true,
        'camera_recovery_error': e.toString(),
        'camera_recovery_camera': camera.name,
      });

      try {
        // Hard reset the camera controller and re-init the same camera.
        _cameraController?.removeListener(_onCameraControllerUpdate);
        await _cameraController?.dispose();
      } catch (_) {
        // Best-effort.
      } finally {
        _cameraController = null;
      }

      // Small delay to let CameraX fully close/rebind (helps on Android TV).
      await Future.delayed(
        Duration(milliseconds: AppConstants.kCameraDisposeToReopenDelayMs),
      );
      await initializeCamera(camera);
      final ctrl2 = _cameraController;
      if (ctrl2 == null || !ctrl2.value.isInitialized) rethrow;
      return await ctrl2.takePicture().timeout(
        _takePictureTimeout,
        onTimeout: () => throw TimeoutException('takePicture timeout (retry)'),
      );
    } on TimeoutException catch (e) {
      // Some CameraX failures show up as async errors and cause takePicture() to hang.
      // Treat timeouts as recoverable once, then retry.
      final camera = _currentCamera;
      if (camera == null) rethrow;
      await _recoverCamera(reason: AppStrings.takePictureTimeout, details: e.toString());
      final ctrl2 = _cameraController;
      if (ctrl2 == null || !ctrl2.value.isInitialized) rethrow;
      return await ctrl2.takePicture().timeout(
        _takePictureTimeout,
        onTimeout: () => throw TimeoutException('takePicture timeout (post-recovery retry)'),
      );
    }
  }

  Future<void> _recoverCamera({
    required String reason,
    required String details,
  }) async {
    if (_isRecoveringCamera) return;
    final now = DateTime.now();
    final last = _lastCameraRecoveryAt;
    if (last != null && now.difference(last) < _cameraRecoveryCooldown) return;
    final camera = _currentCamera;
    if (camera == null) return;

    // Serialize recovery so we don't dispose while another camera operation is active.
    await _withCameraLock(() async {
      _isRecoveringCamera = true;
      final completer = Completer<void>();
      _cameraRecoveryCompleter = completer;
      _lastCameraRecoveryAt = now;
      ErrorReportingManager.log('🛠️ Camera recovery started ($reason)');
      await ErrorReportingManager.setCustomKeys({
        'camera_recovery_reason': reason,
        'camera_recovery_details': details,
        'camera_recovery_camera': camera.name,
        'camera_recovery_deviceType': _deviceType?.toString(),
      });

      try {
        // Best-effort full reset.
        try {
          _cameraController?.removeListener(_onCameraControllerUpdate);
          await _cameraController?.dispose();
        } catch (_) {
          // ignore
        } finally {
          _cameraController = null;
        }
        _cameraGeneration++;

        await Future.delayed(
          Duration(milliseconds: AppConstants.kCameraDisposeToReopenDelayMs),
        );
        await initializeCamera(camera);
        _errorMessage = null;
        notifyListeners();
        ErrorReportingManager.log('✅ Camera recovery completed');
      } catch (e, st) {
        AppLogger.error('Camera recovery failed', error: e, stackTrace: st);
        await ErrorReportingManager.recordError(
          e,
          st,
          reason: 'camera recovery failed',
          extraInfo: {'reason': reason, 'details': details},
          fatal: false,
        );
      } finally {
        _isRecoveringCamera = false;
        completer.complete();
        if (identical(_cameraRecoveryCompleter, completer)) {
          _cameraRecoveryCompleter = null;
        }
      }
    });
  }

  /// Selects a photo from the device gallery
  /// This is a fallback option when camera is not working properly
  Future<void> selectFromGallery() async {
    AppLogger.debug('📂 selectFromGallery() called');
    ErrorReportingManager.log('📂 Gallery selection started');
    
    _isSelectingFromGallery = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final ImagePicker picker = ImagePicker();
      
      AppLogger.debug('📂 Opening image picker...');
      final XFile? imageFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: AppConstants.kGalleryPickerImageQuality,
      );

      if (imageFile == null) {
        AppLogger.debug('⚠️ No image selected from gallery');
        ErrorReportingManager.log('Gallery selection cancelled by user');
        _isSelectingFromGallery = false;
        notifyListeners();
        return;
      }

      AppLogger.debug('✅ Image selected from gallery: ${imageFile.path}');
      ErrorReportingManager.log('✅ Photo selected from gallery');

      // Normalize to same standard format/size as camera capture (JPEG, max 1920px)
      AppLogger.debug('📐 Normalizing gallery photo to standard format...');
      final normalizedFile = await ImageHelper.normalizeAndSaveCapturedPhoto(imageFile);
      AppLogger.debug('✅ Gallery photo normalized and saved');
      
      // Get camera ID (use current camera if available, otherwise use 'gallery')
      final cameraId = _cameraController?.description.name ?? 
                       _currentCamera?.name ?? 
                       'gallery';
      final photoId = _uuid.v4();

      _lockedCaptureCardAspectRatio = null;
      _capturedPhoto = PhotoModel(
        id: photoId,
        imageFile: normalizedFile,
        capturedAt: DateTime.now(),
        cameraId: cameraId,
      );
      _capturedImagePixelSize = null;
      unawaited(_refreshCapturedImagePixelSizeSoon(normalizedFile));

      // Track successful photo selection
      unawaited(ErrorReportingManager.setPhotoCaptureContext(
        photoId: photoId,
        sessionId: _sessionManager.sessionId,
      ));
      await ErrorReportingManager.setCustomKey('photo_source', 'gallery');
      ErrorReportingManager.log('Photo selected from gallery: $photoId');

      notifyListeners();
    } on app_exceptions.CameraException catch (e, stackTrace) {
      _errorMessage = 'Gallery Error:\n${e.message}';
      
      ErrorReportingManager.log('❌ CameraException during gallery selection: ${e.message}');
      await ErrorReportingManager.recordError(
        e,
        stackTrace,
        reason: 'CameraException during gallery selection',
        extraInfo: {
          'message': e.message,
        },
      );
      
      notifyListeners();
    } catch (e, stackTrace) {
      _errorMessage = 'Gallery Selection Failed:\n$e';
      
      ErrorReportingManager.log('❌ Error during gallery selection: $e');
      await ErrorReportingManager.recordError(
        e,
        stackTrace,
        reason: 'Gallery selection failed',
        extraInfo: {
          'error': e.toString(),
        },
      );
      
      notifyListeners();
    } finally {
      _isSelectingFromGallery = false;
      notifyListeners();
    }
  }

  /// Clears the captured photo and any error messages
  void clearCapturedPhoto() {
    // Treat "Retake" as a hard reset of any in-flight UI state so the user can
    // always return to live preview, even if an upload/countdown was running.
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _countdownValue = null;

    _uploadTimer?.cancel();
    _uploadTimer = null;
    _uploadElapsedSeconds = 0;
    _isUploading = false;

    _isCapturing = false;
    _isSelectingFromGallery = false;

    _capturedPhoto = null;
    _capturedImagePixelSize = null;
    _lockedCaptureCardAspectRatio = null;
    _errorMessage = null;
    _previewNonce++;
    notifyListeners();
  }

  /// Clears [errorMessage] only (e.g. after a failed upload) while keeping the capture.
  void clearErrorMessage() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    notifyListeners();
  }

  /// On web only: copy blob-backed [XFile] into memory for reliable [readAsBytes]
  /// during upload. Call under the upload loader, not during shutter.
  Future<XFile> _materializeWebXFile(XFile file, String namePrefix) async {
    if (!kIsWeb) return file;
    WebFlowTrace.log('MATERIALIZE', 'readAsBytes_start');
    final bytes = await file.readAsBytes();
    WebFlowTrace.log('MATERIALIZE', 'readAsBytes_done byteLen=${bytes.length}');
    if (bytes.isEmpty) {
      throw Exception('Image is empty (web materialize)');
    }
    return XFile.fromData(
      bytes,
      name: '${namePrefix}_${DateTime.now().millisecondsSinceEpoch}.jpg',
      mimeType: 'image/jpeg',
    );
  }

  /// Decode pixel size after capture without competing with shutter completion.
  Future<void> _refreshCapturedImagePixelSizeSoon(XFile file) async {
    if (kIsWeb) {
      await Future<void>.delayed(const Duration(milliseconds: 48));
    }
    await _refreshCapturedImagePixelSize(file);
  }

  Future<void> _refreshCapturedImagePixelSize(XFile file) async {
    final path = file.path;
    try {
      final bytes = await file.readAsBytes();
      final buffer = await ImmutableBuffer.fromUint8List(bytes);
      final codec = await instantiateImageCodecFromBuffer(buffer);
      final frame = await codec.getNextFrame();
      if (_capturedPhoto?.imageFile.path != path) {
        frame.image.dispose();
        codec.dispose();
        return;
      }
      _capturedImagePixelSize = Size(
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      );
      frame.image.dispose();
      codec.dispose();
      notifyListeners();
    } catch (e) {
      AppLogger.debug('Could not read captured image pixel size: $e');
      if (_capturedPhoto?.imageFile.path == path) {
        _capturedImagePixelSize = null;
        notifyListeners();
      }
    }
  }

  /// Uploads photo to session (Step 3)
  /// Called when user taps "Continue" button in Capture Photo screen
  /// This uploads the photo and triggers preprocessing in the background
  Future<bool> uploadPhotoToSession() async {
    if (_capturedPhoto == null) {
      _errorMessage = 'No photo captured. Please capture a photo first.';
      notifyListeners();
      return false;
    }

    final sessionId = _sessionManager.sessionId;
    if (sessionId == null) {
      _errorMessage = 'No active session found. Please accept terms first.';
      notifyListeners();
      return false;
    }

    _isUploading = true;
    _errorMessage = null;
    _startUploadTimer();
    notifyListeners();

    WebFlowTrace.reset(label: 'upload');
    final sidShort = sessionId.length <= 8 ? sessionId : '${sessionId.substring(0, 8)}…';
    WebFlowTrace.log('UPLOAD', 'begin sessionId=$sidShort kIsWeb=$kIsWeb');

    // Web: allow one layout frame so the full-screen loader and timer repaint
    // before encode/base64 monopolizes the JS thread.
    if (kIsWeb) {
      WebFlowTrace.log('UPLOAD', 'pre_materialize_delay_16ms_start');
      await Future<void>.delayed(const Duration(milliseconds: 16));
      WebFlowTrace.log('UPLOAD', 'pre_materialize_delay_done');
    }

    try {
      if (kIsWeb) {
        final mat = await _materializeWebXFile(_capturedPhoto!.imageFile, 'upload');
        _capturedPhoto = _capturedPhoto!.copyWith(imageFile: mat);
        notifyListeners();
        WebFlowTrace.log('UPLOAD', 'materialize_copyWith_done');
      }

      // Get the image file from the captured photo
      final imageFile = _capturedPhoto!.imageFile;
      
      ErrorReportingManager.log('📦 Encoding image for upload (upload-optimized size)');
      WebFlowTrace.log('ENCODE', 'ImageHelper.encodeImageForUpload_start');
      
      // Use [ImageHelper.encodeImageForUpload] (not path + [compute]): web camera [XFile]s
      // often have no real filesystem path; bytes must be read before isolate work.
      final base64Image = await ImageHelper.encodeImageForUpload(imageFile);
      WebFlowTrace.log(
        'ENCODE',
        'ImageHelper.encodeImageForUpload_done dataUrlLen=${base64Image.length}',
      );
      
      ErrorReportingManager.log('✅ Image encoded for upload');
      ErrorReportingManager.log('📤 Uploading processed image to API');
      WebFlowTrace.log('PATCH', 'updateSession_photo_start');

      // Step 2: PATCH /api/sessions/{sessionId} with userImageUrl (data URL) + optional metadata.
      final response = await _apiService.updateSession(
        sessionId: sessionId,
        userImageUrl: base64Image,
        selectedThemeId: null,
        framingMetadata: <String, dynamic>{
          'applied': false,
          'mode': 'auto',
          'originalImageUrl': null,
        },
      ).timeout(
        AppConstants.kApiTimeout,
        onTimeout: () => throw TimeoutException(
          'Upload timed out after ${AppConstants.kApiTimeout.inSeconds} seconds',
        ),
      );
      WebFlowTrace.log('PATCH', 'updateSession_photo_done');
      
      ErrorReportingManager.log('✅ Image uploaded successfully');
      
      // Save the response to SessionManager
      _sessionManager.setSessionFromResponse(response);
      WebFlowTrace.log('UPLOAD', 'setSessionFromResponse_done');
      
      // Step 3b: Preprocess image in background (fire-and-forget)
      // This runs validation, compression, and person detection ahead of time
      // Don't wait for it to complete - it's an optimization
      ErrorReportingManager.log('🔄 Triggering background image preprocessing');
      _apiService.preprocessImage(sessionId: sessionId);
      
      WebFlowTrace.log('UPLOAD', 'success preprocess_fireAndForget');
      return true;
    } on TimeoutException catch (e) {
      WebFlowTrace.log('UPLOAD', 'ERROR TimeoutException $e');
      _errorMessage = 'Upload took too long. Please check your connection and try again.';
      return false;
    } on app_exceptions.ApiException catch (e) {
      WebFlowTrace.log('UPLOAD', 'ERROR ApiException ${e.message}');
      _errorMessage = e.message;
      return false;
    } catch (e) {
      WebFlowTrace.log('UPLOAD', 'ERROR $e');
      _errorMessage = 'Failed to upload photo: ${e.toString()}';
      return false;
    } finally {
      _stopUploadTimer();
      _isUploading = false;
      notifyListeners();
    }
  }

  /// Updates session with captured photo and selected theme
  /// Gets the image from the camera file and uploads it via API
  /// @deprecated Use uploadPhotoToSession() instead when uploading just the photo
  Future<bool> updateSessionWithPhoto(String selectedThemeId) async {
    if (_capturedPhoto == null) {
      _errorMessage = 'No photo captured. Please capture a photo first.';
      notifyListeners();
      return false;
    }

    final sessionId = _sessionManager.sessionId;
    if (sessionId == null) {
      _errorMessage = 'No active session found. Please accept terms first.';
      notifyListeners();
      return false;
    }

    _isUploading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // Get the image file from the captured photo
      final imageFile = _capturedPhoto!.imageFile;
      
      final base64Image = await ImageHelper.encodeImageForUpload(imageFile);

      const updateTimeout = Duration(seconds: 60);
      final response = await _apiService.updateSession(
        sessionId: sessionId,
        userImageUrl: base64Image,
        selectedThemeId: selectedThemeId,
        framingMetadata: <String, dynamic>{
          'applied': false,
          'mode': 'auto',
          'originalImageUrl': null,
        },
      ).timeout(
        updateTimeout,
        onTimeout: () => throw TimeoutException(
          'Update timed out after ${updateTimeout.inSeconds} seconds',
        ),
      );

      _sessionManager.setSessionFromResponse(response);
      return true;
    } on TimeoutException {
      _errorMessage = 'Request took too long. Please check your connection and try again.';
      return false;
    } on app_exceptions.ApiException catch (e) {
      _errorMessage = e.message;
      return false;
    } catch (e) {
      _errorMessage = 'Failed to update session: ${e.toString()}';
      return false;
    } finally {
      _isUploading = false;
      notifyListeners();
    }
  }

  /// Eagerly releases camera native buffers. Call before navigating away
  /// so the next screen doesn't overlap with camera heap on low-RAM devices.
  void disposeCamera() {
    try {
      _cameraController?.removeListener(_onCameraControllerUpdate);
      _cameraController?.dispose();
    } catch (e, st) {
      // Best-effort; do not throw from dispose paths.
      AppLogger.error('disposeCamera failed', error: e, stackTrace: st);
    }
    _cameraController = null;
  }

  /// Disposes the camera controller
  @override
  void dispose() {
    _stopUploadTimer();
    disposeCamera();
    super.dispose();
  }
}

