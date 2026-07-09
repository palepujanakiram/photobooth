import 'dart:async';
import 'dart:ui'
    show Size, ImmutableBuffer, instantiateImageCodecFromBuffer;
import 'package:flutter/foundation.dart' show ChangeNotifier, TargetPlatform, defaultTargetPlatform, kIsWeb, visibleForTesting;
import 'package:flutter/services.dart' show MethodChannel, PlatformException;
import 'package:camera/camera.dart';
import 'package:camera/camera.dart' as cam show availableCameras;
import 'package:image_picker/image_picker.dart';
import '../../utils/camera_permission_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'photo_model.dart';
import '../../services/api_service.dart';
import '../../services/face_count_service.dart';
import '../../services/session_manager.dart';
import '../../utils/constants.dart';
import '../../utils/device_classifier.dart';
import '../../utils/app_device_type.dart';
import '../../utils/exceptions.dart' as app_exceptions;
import '../../utils/image_helper.dart';
import '../../utils/platform_capabilities.dart';
import '../../utils/uvc_capture_config.dart';
import 'camera_description_label.dart';
import 'photo_capture_camera_selection_helpers.dart';
import '../../utils/app_strings.dart';
import '../../utils/logger.dart';
import '../../utils/error_reporting_helpers.dart';
import 'photo_capture_camera_error_helpers.dart';
import '../../utils/web_flow_trace.dart';
import '../../utils/web_upload_error_hint.dart';
import '../../services/error_reporting/error_reporting_manager.dart';
import '../../services/capture_sound_service.dart';
import 'package:camera_native_details/camera_native_details.dart';
import 'photo_capture_camera_config.dart';
import 'photo_capture_preview_rotation.dart';
import 'photo_capture_preprocess_helpers.dart';
import 'photo_capture_viewmodel_helpers.dart';

class CaptureViewModel extends ChangeNotifier {
  final ApiService _apiService;
  final SessionManager _sessionManager;
  final Uuid _uuid = const Uuid();
  static List<CameraDescription>? _cachedAvailableCameras;

  /// Whether a prior [loadCameras] / [warmCameraEnumerationCache] filled the static cache.
  static bool get hasEnumerationCache => _cachedAvailableCameras != null;

  /// True when Terms preload enumerated at least one openable camera for POSE.
  static bool hasOpenableCaptureCamera({AppDeviceType? deviceType}) {
    final cached = _cachedAvailableCameras;
    if (cached == null || cached.isEmpty) return false;
    if (kIsWeb) return true;
    return captureCamerasForDevice(
      cameras: cached,
      deviceType: deviceType,
      looksLikeExternalName: looksLikeExternalCameraName,
    ).isNotEmpty;
  }

  @visibleForTesting
  static void resetWebLivePreviewKickstartForTest() {
    _webLivePreviewKickstartDone = false;
  }

  static bool _webLivePreviewKickstartDone = false;
  int _webLivePreviewRecoveryGeneration = 0;

  /// True when POSE should prefer the enumerated CameraX path over UVC probing.
  bool get preferEnumeratedCameraPath {
    final cached = _cachedAvailableCameras;
    if (cached == null || cached.isEmpty) return false;
    return captureCamerasForDevice(
      cameras: cached,
      deviceType: _deviceType,
      looksLikeExternalName: _looksLikeExternalCameraName,
    ).isNotEmpty;
  }

  CameraController? _cameraController;

  /// Set true in [dispose]. Post-await work should bail before mutating state.
  bool _disposed = false;
  bool get isDisposed => _disposed;

  /// No-op once [_disposed] — safe for fire-and-forget camera/upload callbacks.
  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

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

  @visibleForTesting
  static void resetCameraCacheForTest() {
    _cachedAvailableCameras = null;
  }

  @visibleForTesting
  static void setCachedCamerasForTest(List<CameraDescription> cameras) {
    _cachedAvailableCameras = List<CameraDescription>.from(cameras);
  }

  static CameraController? _prewarmedController;
  static CameraDescription? _prewarmedCamera;
  static AppDeviceType? _prewarmedForDeviceType;
  static Future<void>? _prewarmInFlight;

  static bool get hasPrewarmedCamera =>
      _prewarmedController?.value.isInitialized == true;

  static AppDeviceType? get prewarmedDeviceType => _prewarmedForDeviceType;

  /// Waits for Terms-screen prewarm started with [prewarmLiveCamera].
  static Future<void> awaitPrewarmIfInFlight({
    Duration timeout = const Duration(seconds: 16),
  }) async {
    final task = _prewarmInFlight;
    if (task == null) return;
    try {
      await task.timeout(timeout);
    } on TimeoutException {
      AppLogger.debug('Prewarm still in flight after ${timeout.inSeconds}s');
    }
  }

  /// Opens the live CameraX feed during Terms idle time so POSE can adopt instantly.
  static Future<void> prewarmLiveCamera({AppDeviceType? deviceType}) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    if (_prewarmedController?.value.isInitialized == true) return;
    if (_prewarmInFlight != null) {
      await _prewarmInFlight;
      return;
    }
    final task = _prewarmLiveCameraBody(deviceType: deviceType);
    _prewarmInFlight = task;
    try {
      await task;
    } finally {
      if (identical(_prewarmInFlight, task)) {
        _prewarmInFlight = null;
      }
    }
  }

  static Future<void> _prewarmLiveCameraBody({AppDeviceType? deviceType}) async {
    try {
      if (_cachedAvailableCameras == null) {
        await preloadCameras();
      }
      final cached = _cachedAvailableCameras;
      if (cached == null || cached.isEmpty) return;
      await disposePrewarm();
      final candidates = captureCamerasForDevice(
        cameras: cached,
        deviceType: deviceType,
        looksLikeExternalName: looksLikeExternalCameraName,
      );
      if (candidates.isEmpty) return;
      final picked = pickPreferredCaptureCamera(
        cameras: cached,
        deviceType: deviceType,
        looksLikeExternalName: looksLikeExternalCameraName,
      );
      final isExternal = isExternalCaptureCamera(
        picked,
        looksLikeExternalCameraName,
      );
      final ctrl = CameraController(
        picked,
        captureResolutionPreset(
          deviceType: deviceType,
          isExternal: isExternal,
        ),
        enableAudio: false,
        imageFormatGroup: captureStreamFormat(
          deviceType: deviceType,
          isExternal: isExternal,
        ),
      );
      await ctrl.initialize().timeout(const Duration(seconds: 15));
      _prewarmedController = ctrl;
      _prewarmedCamera = picked;
      _prewarmedForDeviceType = deviceType;
      AppLogger.debug(
        '✅ Prewarmed camera: ${cameraDescriptionLabel(picked)}',
      );
    } catch (e, st) {
      AppLogger.debug('Prewarm camera skipped/failed: $e');
      await disposePrewarm();
      unawaited(
        ErrorReportingManager.recordError(
          e,
          st,
          reason: 'prewarmLiveCamera failed',
          fatal: false,
        ),
      );
    }
  }

  static Future<void> disposePrewarm() async {
    final ctrl = _prewarmedController;
    _prewarmedController = null;
    _prewarmedCamera = null;
    _prewarmedForDeviceType = null;
    if (ctrl == null) return;
    try {
      await ctrl.dispose();
    } catch (_) {
      // Best-effort teardown of unused prewarm.
    }
  }

  @visibleForTesting
  static void resetPrewarmForTest() {
    _prewarmedController = null;
    _prewarmedCamera = null;
    _prewarmedForDeviceType = null;
    _prewarmInFlight = null;
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
  int get cameraGeneration => _cameraGeneration;

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
  String? _uploadStatusMessage;

  /// Background upload encode (started after shutter so Continue only PATCHes).
  String? _preparedUploadBase64;
  String? _prepareUploadPhotoId;
  int? _preparedClientFaceCount;
  Future<String>? _prepareUploadFuture;
  
  // Countdown timer for capture
  int? _countdownValue;
  int _countdownGeneration = 0;

  /// Zoom range and current value; null when zoom is not supported.
  double? _minZoom;
  double? _maxZoom;
  double _currentZoom = 1.0;
  static const _zoomLoadTimeout = Duration(seconds: 3);

  /// Max wait for camera enumeration. On devices with only external cameras, CameraX
  /// validation can retry for a long time; we timeout so the UI stays responsive.
  static const _loadCamerasTimeout = Duration(seconds: 25);

  /// Avoid duplicate Bugsnag events when the user taps Retry repeatedly.
  final Set<String> _reportedCameraNotFoundReasons = {};

  /// Camera preview rotation in degrees (0, 90, 180, 270). Persisted in SharedPreferences.
  int _previewRotationDegrees = AppConstants.kCameraPreviewRotationDefault;
  bool _isPreviewRotationConfiguredByUser = false;

  /// Display rotation from Android WindowManager (0–3: ROTATION_0, 90, 180, 270). Used for preview correction and capture lock.
  int _displayRotation = 0;

  CaptureViewModel({
    ApiService? apiService,
    SessionManager? sessionManager,
    CaptureSoundService? captureSoundService,
  })  : _apiService = apiService ?? ApiService(),
        _sessionManager = sessionManager ?? SessionManager(),
        _captureSoundService = captureSoundService ?? CaptureSoundService();

  final CaptureSoundService _captureSoundService;

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
  AppDeviceType? get deviceType => _deviceType;
  bool get isLoadingCameras => _isLoadingCameras;
  bool get isInitializing => _isInitializing;
  bool get isCapturing => _isCapturing;
  bool get isSelectingFromGallery => _isSelectingFromGallery;
  bool get isUploading => _isUploading;
  int get uploadElapsedSeconds => _uploadElapsedSeconds;
  String? get uploadStatusMessage => _uploadStatusMessage;
  bool get isPreparingUploadPayload =>
      _prepareUploadFuture != null && _preparedUploadBase64 == null;
  bool get canContinueUpload =>
      !isCapturing && !isUploading;
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
        unawaited(
          _recoverCamera(
            reason: 'controller.hasError(recoverable)',
            details: desc,
          ).catchError((Object e, StackTrace st) {
            AppLogger.error('Camera recovery failed', error: e, stackTrace: st);
          }),
        );
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
    final (width, height) = previewDisplayDimensions(
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
    final isExternal = isExternalCaptureCamera(
      camera,
      _looksLikeExternalCameraName,
    );
    return _previewQuarterTurnsForSensor(
      sensorOrientation: camera.sensorOrientation % 360,
      isFrontCamera: camera.lensDirection == CameraLensDirection.front,
      isExternalFeed: isExternal,
    );
  }

  /// UVC / USB DSLR feeds are delivered upright; no auto-rotation.
  int get uvcPreviewAutoQuarterTurns => 0;

  int get uvcPreviewEffectiveQuarterTurns =>
      (uvcPreviewAutoQuarterTurns + (_previewRotationDegrees ~/ 90) % 4) % 4;

  Size? uvcPreviewDisplaySizeForCard({
    required double frameWidth,
    required double frameHeight,
  }) {
    if (frameWidth <= 0 || frameHeight <= 0) return null;
    final baseAspect = frameWidth / frameHeight;
    final turns = uvcPreviewEffectiveQuarterTurns;
    final displayAspect = turns.isOdd ? 1 / baseAspect : baseAspect;
    final (width, height) = previewDisplayDimensions(
      previewSize: Size(frameWidth, frameHeight),
      effectiveQuarterTurns: turns,
      displayAspectRatio: displayAspect,
    );
    if (width <= 0 || height <= 0) return null;
    return Size(width, height);
  }

  int _previewQuarterTurnsForSensor({
    required int sensorOrientation,
    required bool isFrontCamera,
    required bool isExternalFeed,
  }) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return 0;
    final applyWorkaround =
        shouldUseLandscapePreviewRotationWorkaround || isExternalFeed;
    return previewAutoQuarterTurnsForSensor(
      applyAndroidRotationWorkaround: applyWorkaround,
      sensorOrientationDegrees: sensorOrientation % 360,
      isFrontCamera: isFrontCamera,
      isExternalFeed: isExternalFeed,
      displayRotationIndex: _displayRotation,
    );
  }

  void _snapshotLockedCaptureCardAspectFromLivePreview() {
    final d = previewDisplaySizeForCard;
    if (d != null && d.height > 0) {
      _lockedCaptureCardAspectRatio =
          (d.width / d.height).clamp(0.35, 2.85);
    }
  }

  /// Locks capture-card aspect from an external preview (e.g. USB/UVC) before teardown.
  void lockCaptureCardAspectRatio(double aspectRatio) {
    if (aspectRatio <= 0) return;
    _lockedCaptureCardAspectRatio = aspectRatio.clamp(0.35, 2.85);
  }

  /// Resets manual preview rotation when switching to USB/UVC (built-in values are often wrong).
  void applyDefaultPreviewRotationForUvc() {
    if (_previewRotationDegrees == 0) return;
    _previewRotationDegrees = 0;
    notifyListeners();
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
  bool get isDesktopCaptureMode => usesDesktopPhotoPicker;

  bool get isReady {
    if (isDesktopCaptureMode) return !_isLoadingCameras;
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

  CameraDescription _pickDefaultCamera(List<CameraDescription> cameras) {
    return _pickDefaultCameraFromList(cameras);
  }

  static CameraDescription _pickDefaultCameraFromList(
    List<CameraDescription> cameras,
  ) {
    if (cameras.isEmpty) {
      throw StateError('No cameras available');
    }
    final byName = cameras
        .where((c) => looksLikeExternalCameraName(c.name))
        .toList();
    if (byName.isNotEmpty) {
      return byName.first;
    }
    final byDirection = cameras
        .where((c) => c.lensDirection == CameraLensDirection.external)
        .toList();
    if (byDirection.isNotEmpty) {
      return byDirection.first;
    }
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

  /// Transfers the Terms-screen prewarm into this screen instance.
  bool adoptPrewarmIfAvailable() => _tryAdoptPrewarmedCamera();

  bool _tryAdoptPrewarmedCamera() {
    final ctrl = _prewarmedController;
    final camera = _prewarmedCamera;
    final prewarmedType = _prewarmedForDeviceType;
    if (ctrl == null || camera == null || !ctrl.value.isInitialized) {
      return false;
    }
    if (_deviceType != null &&
        prewarmedType != null &&
        _deviceType != prewarmedType) {
      unawaited(disposePrewarm());
      return false;
    }
    _prewarmedController = null;
    _prewarmedCamera = null;
    _prewarmedForDeviceType = null;

    if (_cachedAvailableCameras != null) {
      _applyCachedCameraList();
    } else {
      _availableCameras = [camera];
    }
    _currentCamera = camera;
    _cameraController = ctrl;
    _cameraGeneration++;
    _errorMessage = null;
    _minZoom = null;
    _maxZoom = null;
    _currentZoom = 1.0;
    ctrl.addListener(_onCameraControllerUpdate);
    _markCameraAvailabilityRestored();
    unawaited(
      _finishCameraSetup(camera).catchError((Object e, StackTrace st) {
        AppLogger.error('finishCameraSetup failed', error: e, stackTrace: st);
      }),
    );
    notifyListeners();
    AppLogger.debug('✅ Adopted prewarmed camera on POSE entry');
    return true;
  }

  /// True if camera name looks like a real external device (e.g. iOS UUID).
  /// Excludes built-in cameras whose names contain "built-in" (plugin can misreport direction).
  bool _looksLikeExternalCameraName(String name) =>
      looksLikeExternalCameraName(name);

  /// Set device type from UI (from [DeviceClassifier.getDeviceType]).
  /// Used to filter cameras: tablet/TV → external first with built-in fallback.
  void setDeviceType(AppDeviceType? type) {
    final changed = _deviceType != type;
    _deviceType = type;
    if (changed && _cachedAvailableCameras != null) {
      _applyCachedCameraList();
      notifyListeners();
    }
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

  void _applyCachedCameraList() {
    if (_cachedAvailableCameras == null) return;
    final filtered = captureCamerasForDevice(
      cameras: _cachedAvailableCameras!,
      deviceType: _deviceType,
      looksLikeExternalName: _looksLikeExternalCameraName,
    );
    _availableCameras = filtered;
    if (filtered.isEmpty) {
      _errorMessage = kIsWeb
          ? 'No camera detected. Allow camera access in the browser, or use Gallery if enabled.'
          : 'No cameras available';
      unawaited(
        reportCameraNotFound(
          reason: 'No cameras detected',
          extraInfo: const {'source': 'cached_enumeration'},
        ),
      );
      return;
    }
    _markCameraAvailabilityRestored();
    if (_currentCamera == null && _availableCameras.isNotEmpty) {
      _currentCamera = _pickDefaultCamera(_availableCameras);
    }
  }

  /// Reports missing/unavailable camera to Bugsnag (once per [reason] per session until restored).
  Future<void> reportCameraNotFound({
    required String reason,
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? extraInfo,
  }) async {
    if (_reportedCameraNotFoundReasons.contains(reason)) return;
    _reportedCameraNotFoundReasons.add(reason);

    ErrorReportingManager.log('❌ $reason');
    if (error != null && isHandledCameraPipelineError(error)) {
      return;
    }

    await ErrorReportingManager.recordError(
      error ?? Exception(reason),
      stackTrace ?? StackTrace.current,
      reason: reason,
      extraInfo: {
        'platform': defaultTargetPlatform.name,
        if (_deviceType != null) 'deviceType': _deviceType.toString(),
        if (extraInfo != null) ...extraInfo,
      },
      fatal: false,
    );
  }

  /// Clears dedupe so a later genuine outage can be reported again.
  void markCameraAvailabilityRestored() {
    _reportedCameraNotFoundReasons.clear();
  }

  void _markCameraAvailabilityRestored() => markCameraAvailabilityRestored();

  Future<bool> _ensureAndroidCameraPermission() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return true;
    }
    final granted = await ensureCameraPermission(requestIfNeeded: false);
    if (granted) return true;
    AppLogger.debug(
      '📷 Camera permission not granted (prompted on Terms screen)',
    );
    _errorMessage = 'Camera permission is required to detect and use cameras.';
    unawaited(
      reportCameraNotFound(
        reason: 'Camera permission denied',
        extraInfo: const {'permission_status': 'denied'},
      ),
    );
    return false;
  }

  Future<void> _reportEmptyCameraEnumeration() async {
    await reportCameraNotFound(
      reason: 'No cameras detected',
      extraInfo: const {
        'source': 'empty_enumeration',
        'message': 'availableCameras() returned empty list; no exception thrown',
      },
    );
  }

  void _assignEnumeratedCameras(List<CameraDescription> allCameras) {
    if (allCameras.isEmpty) {
      _errorMessage = kIsWeb
          ? 'No camera detected. Allow camera access in the browser, or use Gallery if enabled.'
          : 'No cameras available';
      unawaited(_reportEmptyCameraEnumeration());
    } else {
      _markCameraAvailabilityRestored();
    }
    AppLogger.debug('📷 Detected ${allCameras.length} camera(s):');
    for (final c in allCameras) {
      AppLogger.debug('  - Name: "${c.name}", Direction: ${c.lensDirection}');
    }
    _cachedAvailableCameras = List<CameraDescription>.from(allCameras);
    final filtered = captureCamerasForDevice(
      cameras: allCameras,
      deviceType: _deviceType,
      looksLikeExternalName: _looksLikeExternalCameraName,
    );
    _availableCameras = filtered;
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
    if (_currentCamera != null &&
        !_availableCameras.any((c) => c.name == _currentCamera!.name)) {
      _currentCamera = null;
    }
    if (_currentCamera == null && _availableCameras.isNotEmpty) {
      _currentCamera = _pickDefaultCamera(_availableCameras);
      AppLogger.debug(
        '📷 Auto-selected camera: ${cameraDescriptionLabel(_currentCamera!)}',
      );
    }
  }

  /// Reloads the camera list from the platform (e.g. after plugging in USB).
  Future<void> refreshCameraEnumeration() async {
    await loadCameras(forceRefresh: true);
  }

  /// Sets [capturedPhoto] from an externally provided file (e.g. USB/UVC camera).
  /// This reuses the same normalization and upload-prep pipeline as the built-in camera.
  Future<void> setCapturedPhotoFromExternalFile({
    required XFile rawFile,
    required String cameraId,
    bool force = false,
  }) async {
    if (!force && (_isCapturing || _isUploading)) return;
    final isUvc = cameraId.startsWith('uvc:');
    _isCapturing = true;
    _errorMessage = null;
    notifyListeners();

    // Let the capture flash / overlay paint before heavy isolate work.
    await Future<void>.delayed(Duration.zero);

    try {
      XFile savedFile;
      try {
        savedFile = await ImageHelper.normalizeAndSaveCapturedPhoto(
          rawFile,
          flipHorizontal: false,
          fixBgrChannelOrder: isUvc,
          maxDimension: isUvc ? UvcCaptureConfig.normalizeMaxDimension : null,
          jpegQuality: isUvc ? UvcCaptureConfig.normalizeJpegQuality : null,
        );
        if (isUvc) {
          await ImageHelper.tryDeleteLocalFile(rawFile.path);
        }
      } catch (normalizeError, normalizeSt) {
        if (!isUvc) rethrow;
        AppLogger.error(
          'UVC normalize failed; using raw still',
          error: normalizeError,
          stackTrace: normalizeSt,
        );
        savedFile = rawFile;
      }
      if (isUvc) {
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
      await _assignCapturedPhotoModel(
        savedFile,
        cameraIdOverride: cameraId,
        skipCapturedImagePixelSizeDecode: isUvc,
        uploadPrepDelay: isUvc
            ? UvcCaptureConfig.uploadPrepDelay
            : const Duration(milliseconds: 48),
        skipUploadPrep:
            isUvc && UvcCaptureConfig.deferUploadPrepUntilContinue,
      );
    } catch (e, st) {
      _errorMessage = 'USB camera capture failed: $e';
      await ErrorReportingManager.recordError(
        e,
        st,
        reason: 'setCapturedPhotoFromExternalFile failed',
        extraInfo: {'cameraId': cameraId},
        fatal: false,
      );
      notifyListeners();
    } finally {
      _isCapturing = false;
      notifyListeners();
    }
  }

  /// Loads available cameras when user opens Capture screen.
  Future<void> loadCameras({bool forceRefresh = false}) async {
    if (usesDesktopPhotoPicker) {
      _isLoadingCameras = false;
      _availableCameras = [];
      notifyListeners();
      return;
    }

    if (!forceRefresh && _cachedAvailableCameras != null) {
      _applyCachedCameraList();
      _isLoadingCameras = false;
      _errorMessage = null;
      notifyListeners();
      return;
    }

    _isLoadingCameras = true;
    _errorMessage = null;
    notifyListeners();

    try {
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
    } on TimeoutException catch (e, stackTrace) {
      _errorMessage = cameraLoadFailureMessage(e);
      unawaited(
        reportCameraNotFound(
          reason: 'Camera enumeration timed out',
          error: e,
          stackTrace: stackTrace,
          extraInfo: {
            'timeout_seconds': _loadCamerasTimeout.inSeconds,
          },
        ),
      );
    } on PlatformException catch (e, stackTrace) {
      _errorMessage = cameraLoadFailureMessage(e);
      unawaited(
        reportCameraNotFound(
          reason: 'loadCameras failed',
          error: e,
          stackTrace: stackTrace,
          extraInfo: {
            'error': e.toString(),
            'errorType': e.runtimeType.toString(),
          },
        ),
      );
    } catch (e, stackTrace) {
      _errorMessage = cameraLoadFailureMessage(e);
      if (!isHandledCameraPipelineError(e)) {
        await ErrorReportingManager.recordError(
          e,
          stackTrace,
          reason: 'loadCameras failed',
          extraInfo: {
            'error': e.toString(),
            'errorType': e.runtimeType.toString(),
          },
          fatal: false,
        );
      }
      notifyListeners();
    } finally {
      _isLoadingCameras = false;
      notifyListeners();
    }
  }

  /// Fills the static enumeration cache without toggling [isLoadingCameras].
  ///
  /// When the first POSE visit uses UVC only, [loadCameras] never runs; warming
  /// the cache avoids a 15–25s CameraX enumeration on the next visit.
  Future<void> warmCameraEnumerationCache() async {
    if (_cachedAvailableCameras != null || usesDesktopPhotoPicker) return;
    try {
      if (!await _ensureAndroidCameraPermission()) return;
      final allCameras = await cam.availableCameras().timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('warmCameraEnumerationCache'),
      );
      _assignEnumeratedCameras(allCameras);
    } catch (_) {
      // Best-effort background warm.
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

    if (!forceRefresh &&
        _cameraController != null &&
        _cameraController!.value.isInitialized &&
        _availableCameras.isNotEmpty) {
      AppLogger.debug('✅ Camera already ready — skipping reset');
      return;
    }

    // Clear any captured photo
    _capturedPhoto = null;
    _capturedImagePixelSize = null;
    _lockedCaptureCardAspectRatio = null;
    
    const initTimeout = Duration(seconds: 25);
    try {
      await (() async {
        if (!forceRefresh) {
          await CaptureViewModel.awaitPrewarmIfInFlight();
          if (_cameraController?.value.isInitialized == true &&
              _availableCameras.isNotEmpty) {
            return;
          }
          if (_tryAdoptPrewarmedCamera()) {
            return;
          }
        }

        // Dispose current camera controller before a fresh open.
        if (_cameraController != null) {
          AppLogger.debug('   Disposing current camera controller...');
          final ctrl = _cameraController;
          _cameraController = null;
          _cameraGeneration++;
          notifyListeners();
          try {
            ctrl!.removeListener(_onCameraControllerUpdate);
            await ctrl.dispose();
            if (kIsWeb) {
              await delayBeforeCameraReopen();
            }
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
        }

        // Clear current camera selection
        _currentCamera = null;
        
        // Clear any previous errors
        _errorMessage = null;

        await loadCameras(forceRefresh: forceRefresh);
        if (!forceRefresh && _tryAdoptPrewarmedCamera()) {
          return;
        }
        await disposePrewarm();
        if (_availableCameras.isNotEmpty) {
          _currentCamera = _pickDefaultCamera(_availableCameras);
          AppLogger.debug(
            '📷 Selected camera: ${cameraDescriptionLabel(_currentCamera!)}',
          );
          await initializeCamera(_currentCamera!);
        } else {
          AppLogger.debug('⚠️ No cameras available');
          _errorMessage = 'No cameras available';
          unawaited(
            reportCameraNotFound(
              reason: 'No cameras detected',
              extraInfo: const {'source': 'reset_and_initialize'},
            ),
          );
          notifyListeners();
        }
      })().timeout(initTimeout);
    } on TimeoutException catch (e, stackTrace) {
      AppLogger.debug('⏱️ Camera initialization timed out after ${initTimeout.inSeconds}s');
      _errorMessage = 'Camera took too long to start. Please try again.';
      unawaited(
        reportCameraNotFound(
          reason: 'Camera initialization timed out',
          error: e,
          stackTrace: stackTrace,
          extraInfo: {'timeout_seconds': initTimeout.inSeconds},
        ),
      );
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
      unawaited(
        _finishCameraSetup(camera).catchError((Object e, StackTrace st) {
          AppLogger.error('finishCameraSetup failed', error: e, stackTrace: st);
        }),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _disposeCameraControllerForSwitch() async {
    final ctrl = _cameraController;
    if (ctrl == null) return;
    AppLogger.debug('🔄 Disposing existing camera controller before switch...');
    _cameraController = null;
    _cameraGeneration++;
    notifyListeners();
    try {
      ctrl.removeListener(_onCameraControllerUpdate);
      await ctrl.dispose();
    } catch (e) {
      AppLogger.debug('   ⚠️ Warning: Error disposing existing controller: $e');
    }
    await Future.delayed(
      Duration(milliseconds: AppConstants.kCameraDisposeToReopenDelayMs),
    );
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
    _markCameraAvailabilityRestored();
    unawaited(
      _finishCameraSetup(camera).catchError((Object e, StackTrace st) {
        AppLogger.error('finishCameraSetup failed', error: e, stackTrace: st);
      }),
    );
    if (kIsWeb) {
      _previewNonce++;
      notifyListeners();
      unawaited(_ensureWebLivePreviewPainted(camera));
    }
  }

  /// Reopen once per browser session — camera_web often paints only after dispose/reopen.
  Future<void> _ensureWebLivePreviewPainted(CameraDescription camera) async {
    if (!kIsWeb || _disposed || _webLivePreviewKickstartDone) return;
    final generation = ++_webLivePreviewRecoveryGeneration;
    await delayBeforeCameraReopen();
    if (_disposed || generation != _webLivePreviewRecoveryGeneration) return;
    if (_capturedPhoto != null) return;

    try {
      AppLogger.debug('Web live preview warm-up: reopening camera');
      _webLivePreviewKickstartDone = true;
      _previewNonce++;
      _cameraGeneration++;
      notifyListeners();
      await _hardResetCameraController();
      await delayBeforeCameraReopen();
      await initializeCamera(camera);
      _previewNonce++;
      notifyListeners();
    } catch (e, st) {
      AppLogger.error(
        'Web live preview recovery failed',
        error: e,
        stackTrace: st,
      );
    }
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
      _errorMessage = cameraLoadFailureMessage(e);
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
        fatal: false,
      );
      return;
    }
    if (e is PlatformException) {
      _errorMessage = cameraLoadFailureMessage(e);
      ErrorReportingManager.log('❌ Platform camera error during initialization');
      await ErrorReportingManager.recordError(
        e,
        stackTrace,
        reason: 'Camera platform exception',
        extraInfo: {
          'message': e.message,
          'code': e.code,
          'camera_name': camera.name,
        },
        fatal: false,
      );
      return;
    }
    _errorMessage = cameraLoadFailureMessage(e);
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
    if (controller == null || !controller.value.isInitialized || _disposed) {
      return;
    }

    try {
      final rotation = await _fetchDisplayRotation();
      if (_disposed) return;
      _displayRotation = rotation;
      AppLogger.debug('   Display rotation: $rotation');
      await maybeLockAndroidPortraitCapture(
        controller: controller,
        camera: camera,
        displayRotation: rotation,
      );
      if (_disposed) return;
      await _applyDefaultPreviewRotationForDevice();
      notifyListeners();
    } catch (_) {
      // Preview can still work without this metadata.
    }

    if (_disposed) return;
    await _loadZoomInBackground();
    if (_disposed) return;

    final details = await fetchNativeCameraDetails(camera.name);
    if (_disposed) return;
    _nativeCameraDetails = details;
    if (details != null) {
      logNativeCameraDetails(details);
    }
    notifyListeners();
    unawaited(warmUpCaptureShutterSound());
  }

  /// Loads zoom range in background with timeout so init never hangs.
  Future<void> _loadZoomInBackground() async {
    final ctrl = _cameraController;
    if (ctrl == null || !ctrl.value.isInitialized || _disposed) return;

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
      if (_disposed) return;
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

  /// Plays the capture shutter cue (best-effort; does not block capture).
  Future<void> playCaptureShutterSound() => _captureSoundService.playShutter();

  /// Warms the shutter clip while the live feed is idle.
  Future<void> warmUpCaptureShutterSound() =>
      _captureSoundService.warmUp();

  /// Runs a countdown then [captureAction] (built-in CameraX or UVC).
  Future<void> captureWithCountdown(
    Future<void> Function() captureAction, {
    required bool Function() canStart,
  }) async {
    if (!canStart() || _isCapturing || _countdownValue != null) {
      return;
    }

    AppLogger.debug(
      '📸 Starting capture countdown (${AppConstants.kCaptureCountdownSeconds}s)...',
    );

    final generation = ++_countdownGeneration;
    _countdownValue = AppConstants.kCaptureCountdownSeconds;
    notifyListeners();

    try {
      for (var step = _countdownValue!; step >= 1; step--) {
        if (generation != _countdownGeneration || !canStart()) return;
        _countdownValue = step;
        notifyListeners();
        if (step > 1) {
          await Future<void>.delayed(const Duration(seconds: 1));
        }
      }

      if (generation != _countdownGeneration || !canStart()) return;
      _countdownValue = null;
      notifyListeners();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (generation != _countdownGeneration || !canStart()) return;
      await captureAction();
    } finally {
      if (generation == _countdownGeneration) {
        _countdownValue = null;
        notifyListeners();
      }
    }
  }

  /// Starts a countdown and then captures a photo
  /// Countdown duration is configured via AppConstants.kCaptureCountdownSeconds
  Future<void> capturePhotoWithCountdown() async {
    await captureWithCountdown(
      capturePhoto,
      canStart: () => isReady,
    );
  }
  
  /// Cancels the countdown if in progress
  void cancelCountdown() {
    _countdownGeneration++;
    unawaited(_captureSoundService.cancel());
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

  Future<void> _assignCapturedPhotoModel(
    XFile savedFile, {
    String? cameraIdOverride,
    bool skipCapturedImagePixelSizeDecode = false,
    Duration uploadPrepDelay = const Duration(milliseconds: 48),
    bool skipUploadPrep = false,
  }) async {
    final cameraId = cameraIdOverride ??
        _cameraController?.description.name ??
        _currentCamera?.name;
    final photoId = _uuid.v4();
    if (cameraIdOverride == null) {
      _snapshotLockedCaptureCardAspectFromLivePreview();
    }
    _capturedPhoto = PhotoModel(
      id: photoId,
      imageFile: savedFile,
      capturedAt: DateTime.now(),
      cameraId: cameraId,
    );
    _capturedImagePixelSize = null;
    if (!kIsWeb && !skipCapturedImagePixelSizeDecode) {
      unawaited(_refreshCapturedImagePixelSizeSoon(savedFile));
    }
    unawaited(ErrorReportingManager.setPhotoCaptureContext(
      photoId: photoId,
      sessionId: _sessionManager.sessionId,
    ));
    ErrorReportingManager.log('Photo captured successfully: $photoId');
    WebFlowTrace.log('CAPTURE', 'photoModel_set photoId=$photoId');
    if (!skipUploadPrep) {
      _kickoffUploadPreparation(initialDelay: uploadPrepDelay);
    }
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
      unawaited(playCaptureShutterSound());
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
    return _withCameraLock(() => _captureSingleFrameFallbackLocked(
      reason: reason,
      details: details,
    ));
  }

  Future<XFile> _captureSingleFrameFallbackLocked({
    required String reason,
    required String details,
  }) async {
    final ctrl = _cameraController;
    final camera = _currentCamera;
    if (!androidStreamFallbackCaptureEligible(
      camera: camera,
      deviceType: _deviceType,
    )) {
      throw CameraException(
        'captureFailed',
        'Still capture failed ($reason): $details',
      );
    }

    await waitForInFlightCameraRecovery(_cameraRecoveryCompleter);

    if (ctrl == null || !ctrl.value.isInitialized || camera == null) {
      throw CameraException(
        'cameraNotReady',
        'Camera not initialized for fallback capture',
      );
    }

    final gen = _cameraGeneration;
    await _logStreamFallbackCaptureStart(camera.name, reason, details);

    try {
      final file = await grabStreamFrameAsJpegFile(
        controller: ctrl,
        streamTimeout: _singleFrameStreamTimeout,
      );
      if (_cameraGeneration != gen || !identical(_cameraController, ctrl)) {
        throw CameraException(
          'cameraRestarted',
          'Camera restarted during fallback capture',
        );
      }
      return file;
    } catch (e, st) {
      await _recordStreamFallbackCaptureError(e, st, camera.name, reason, details);
      rethrow;
    }
  }

  Future<void> _logStreamFallbackCaptureStart(
    String cameraName,
    String reason,
    String details,
  ) async {
    ErrorReportingManager.log('🧯 Fallback capture: grabbing single streamed frame');
    await ErrorReportingManager.setCustomKeys({
      'camera_fallback_capture': true,
      'camera_fallback_reason': reason,
      'camera_fallback_details': details,
      'camera_fallback_camera': cameraName,
    });
  }

  Future<void> _recordStreamFallbackCaptureError(
    Object e,
    StackTrace st,
    String cameraName,
    String reason,
    String details,
  ) async {
    AppLogger.error('Fallback single-frame capture failed', error: e, stackTrace: st);
    await ErrorReportingManager.recordError(
      e,
      st,
      reason: 'fallback single-frame capture failed',
      extraInfo: {
        'fallback_reason': reason,
        'fallback_details': details,
        'camera': cameraName,
      },
      fatal: false,
    );
  }

  Future<XFile> _takePictureWithRecovery() async {
    final ctrl = _cameraController;
    if (ctrl == null || !ctrl.value.isInitialized) {
      throw CameraException('cameraNotReady', 'Camera controller not initialized');
    }

    await waitForInFlightCameraRecovery(_cameraRecoveryCompleter);

    try {
      return await takePictureWithTimeout(ctrl, _takePictureTimeout);
    } on CameraException catch (e) {
      return _retryTakePictureAfterRecoverableError(e);
    } on TimeoutException catch (e) {
      return _retryTakePictureAfterTimeout(e);
    }
  }

  Future<XFile> _retryTakePictureAfterRecoverableError(CameraException e) async {
    if (!isRecoverableTakePictureError(e.toString().toLowerCase())) throw e;
    if (!_isCapturing) throw e;
    if (!canAttemptCameraRecovery(
      lastRecoveryAt: _lastCameraRecoveryAt,
      cooldown: _cameraRecoveryCooldown,
    )) {
      throw e;
    }

    final camera = _currentCamera;
    if (camera == null) throw e;

    _lastCameraRecoveryAt = DateTime.now();
    await _logTakePictureRecoveryAttempt(camera.name, e);
    await _hardResetCameraController();
    await delayBeforeCameraReopen();
    await initializeCamera(camera);
    return _takePictureAfterRecovery('takePicture timeout (retry)');
  }

  Future<XFile> _retryTakePictureAfterTimeout(TimeoutException e) async {
    final camera = _currentCamera;
    if (camera == null) throw e;
    await _recoverCamera(
      reason: AppStrings.takePictureTimeout,
      details: e.toString(),
    );
    return _takePictureAfterRecovery(
      'takePicture timeout (post-recovery retry)',
    );
  }

  Future<void> _logTakePictureRecoveryAttempt(
    String cameraName,
    CameraException e,
  ) async {
    ErrorReportingManager.log(
      '🔁 CameraX recoverable error; re-initializing camera and retrying takePicture',
    );
    await ErrorReportingManager.setCustomKeys({
      'camera_recovery_attempted': true,
      'camera_recovery_error': e.toString(),
      'camera_recovery_camera': cameraName,
    });
  }

  Future<void> _hardResetCameraController() async {
    final ctrl = _cameraController;
    _cameraController = null;
    if (ctrl != null) {
      _cameraGeneration++;
      notifyListeners();
      try {
        ctrl.removeListener(_onCameraControllerUpdate);
        await ctrl.dispose();
      } catch (_) {
        // Best-effort.
      }
    }
  }

  Future<XFile> _takePictureAfterRecovery(String timeoutLabel) async {
    final ctrl2 = _cameraController;
    if (ctrl2 == null || !ctrl2.value.isInitialized) {
      throw CameraException('cameraNotReady', 'Camera controller not initialized');
    }
    return ctrl2.takePicture().timeout(
      _takePictureTimeout,
      onTimeout: () => throw TimeoutException(timeoutLabel),
    );
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
        final ctrl = _cameraController;
        _cameraController = null;
        _cameraGeneration++;
        notifyListeners();
        if (ctrl != null) {
          try {
            ctrl.removeListener(_onCameraControllerUpdate);
            await ctrl.dispose();
          } catch (_) {
            // ignore
          }
        }

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

  /// Windows / macOS / Linux: pick from webcam or file (no `camera` plugin).
  Future<void> capturePhotoFromDesktopPicker({bool preferCamera = true}) async {
    if (!usesDesktopPhotoPicker || _isCapturing || _isSelectingFromGallery) {
      return;
    }

    _isCapturing = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final picker = ImagePicker();
      XFile? imageFile;
      if (preferCamera) {
        try {
          imageFile = await picker.pickImage(
            source: ImageSource.camera,
            maxWidth: 1920,
            maxHeight: 1080,
            imageQuality: AppConstants.kGalleryPickerImageQuality,
          );
        } catch (_) {
          imageFile = null;
        }
      }
      imageFile ??= await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: AppConstants.kGalleryPickerImageQuality,
      );

      if (imageFile == null) {
        return;
      }

      final normalizedFile =
          await ImageHelper.normalizeAndSaveCapturedPhoto(imageFile);
      unawaited(playCaptureShutterSound());
      await _assignCapturedPhotoModel(
        normalizedFile,
        cameraIdOverride: 'desktop',
      );
    } catch (e, st) {
      _errorMessage = 'Failed to capture photo: $e';
      await ErrorReportingManager.recordError(
        e,
        st,
        reason: 'desktop picker capture failed',
        fatal: false,
      );
    } finally {
      _isCapturing = false;
      notifyListeners();
    }
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
      const cameraId = 'gallery';
      final photoId = _uuid.v4();

      _lockedCaptureCardAspectRatio = null;
      _capturedPhoto = PhotoModel(
        id: photoId,
        imageFile: normalizedFile,
        capturedAt: DateTime.now(),
        cameraId: cameraId,
      );
      _capturedImagePixelSize = null;
      if (!kIsWeb) {
        unawaited(_refreshCapturedImagePixelSizeSoon(normalizedFile));
      }

      // Track successful photo selection
      unawaited(ErrorReportingManager.setPhotoCaptureContext(
        photoId: photoId,
        sessionId: _sessionManager.sessionId,
      ));
      await ErrorReportingManager.setCustomKey('photo_source', 'gallery');
      ErrorReportingManager.log('Photo selected from gallery: $photoId');
      _kickoffUploadPreparation();

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

  /// Re-opens the live camera preview after [clearCapturedPhoto] (Retake / back).
  ///
  /// Stream-only and external/Android TV paths often leave the preview texture
  /// stale after capture; a controlled re-init avoids "Camera not ready" on the
  /// next shot.
  Future<void> resumeLivePreviewAfterRetake() async {
    if (_capturedPhoto != null || _isCapturing) return;

    final camera = _currentCamera;
    if (camera == null) {
      await resetAndInitializeCameras();
      return;
    }

    final ctrl = _cameraController;
    final needsReinit = ctrl == null ||
        !ctrl.value.isInitialized ||
        ctrl.value.hasError ||
        _shouldUseStreamOnlyCapture();

    if (!needsReinit) {
      notifyListeners();
      return;
    }

    try {
      await _hardResetCameraController();
      _cameraGeneration++;
      await delayBeforeCameraReopen();
      await initializeCamera(camera);
    } catch (e, st) {
      AppLogger.error(
        'resumeLivePreviewAfterRetake failed',
        error: e,
        stackTrace: st,
      );
      _errorMessage =
          'Failed to restore camera preview. Tap reload to try again.';
      notifyListeners();
    }
  }

  /// Clears the captured photo and any error messages
  void clearCapturedPhoto() {
    // Treat "Retake" as a hard reset of any in-flight UI state so the user can
    // always return to live preview, even if an upload/countdown was running.
    _countdownGeneration++;
    unawaited(_captureSoundService.cancel());
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
    _uploadStatusMessage = null;
    _resetUploadPreparation();
    _previewNonce++;
    notifyListeners();
  }

  void _resetUploadPreparation() {
    _preparedUploadBase64 = null;
    _prepareUploadPhotoId = null;
    _preparedClientFaceCount = null;
    _prepareUploadFuture = null;
  }

  /// Drops in-memory upload payload after PATCH (base64 can be several MB).
  void _releaseUploadPayloadMemory() {
    _resetUploadPreparation();
  }

  /// Background encode while the user reviews a UVC still ([UvcCaptureConfig.deferUploadPrepUntilContinue]).
  void kickoffDeferredUploadPreparation({
    Duration initialDelay = Duration.zero,
  }) {
    _kickoffUploadPreparation(initialDelay: initialDelay);
  }

  /// Marks the Continue upload flow as started so the UI can show progress
  /// before native camera teardown or JPEG encode runs.
  void beginContinueUpload() {
    if (_isUploading || _capturedPhoto == null) return;
    _isUploading = true;
    _errorMessage = null;
    _uploadStatusMessage = 'Preparing photo…';
    _startUploadTimer();
    notifyListeners();
  }

  void _kickoffUploadPreparation({
    Duration initialDelay = const Duration(milliseconds: 48),
  }) {
    final photo = _capturedPhoto;
    if (photo == null) return;
    if (_preparedUploadBase64 != null && _prepareUploadPhotoId == photo.id) {
      return;
    }
    if (_prepareUploadFuture != null) {
      return;
    }
    if (_prepareUploadPhotoId != null && _prepareUploadPhotoId != photo.id) {
      _resetUploadPreparation();
    }
    WebFlowTrace.log('UPLOAD_PREP', 'kickoff photoId=${photo.id}');
    _prepareUploadFuture = () async {
      await Future<void>.delayed(initialDelay);
      if (_capturedPhoto?.id != photo.id) {
        throw StateError('Photo changed before upload prep');
      }
      try {
        final b64 = await _buildUploadPayload(photo);
        if (_capturedPhoto?.id == photo.id) {
          _preparedUploadBase64 = b64;
          _prepareUploadPhotoId = photo.id;
        }
        return b64;
      } catch (e) {
        WebFlowTrace.log('UPLOAD_PREP', 'ERROR $e');
        rethrow;
      } finally {
        if (_preparedUploadBase64 == null) {
          _prepareUploadFuture = null;
        }
        notifyListeners();
      }
    }();
    unawaited(_prepareUploadFuture);
  }

  Future<String> _ensureUploadBase64Ready() async {
    final photo = _capturedPhoto;
    if (photo == null) {
      throw Exception('No photo captured');
    }
    if (_preparedUploadBase64 != null && _prepareUploadPhotoId == photo.id) {
      return _preparedUploadBase64!;
    }
    if (_prepareUploadFuture != null) {
      return _prepareUploadFuture!;
    }
    _prepareUploadFuture = _buildUploadPayload(photo);
    try {
      final b64 = await _prepareUploadFuture!;
      if (_capturedPhoto?.id == photo.id) {
        _preparedUploadBase64 = b64;
        _prepareUploadPhotoId = photo.id;
      }
      return b64;
    } finally {
      _prepareUploadFuture = null;
    }
  }

  Future<String> _buildUploadPayload(PhotoModel photo) async {
    var imageFile = photo.imageFile;
    if (kIsWeb) {
      imageFile = await _materializeWebXFile(imageFile, 'upload');
      if (_capturedPhoto?.id == photo.id) {
        _capturedPhoto = photo.copyWith(imageFile: imageFile);
      }
    }
    WebFlowTrace.log('UPLOAD_PREP', 'encode_start');
    final base64 = await ImageHelper.encodeImageForUpload(imageFile);
    WebFlowTrace.log('UPLOAD_PREP', 'encode_done len=${base64.length}');
    final isUvc = photo.cameraId?.startsWith('uvc:') ?? false;
    if (isUvc) {
      // Face ML Kit decodes the full image again — skip on UVC/tablet to avoid OOM;
      // server preprocess refines person count after PATCH.
      _preparedClientFaceCount = 0;
      WebFlowTrace.log('UPLOAD_PREP', 'face_skipped uvc=true');
    } else {
      _preparedClientFaceCount = await detectFaceCountFromXFile(imageFile);
      WebFlowTrace.log(
        'UPLOAD_PREP',
        'face_done count=$_preparedClientFaceCount',
      );
    }
    return base64;
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
    final bytes = await file.readAsBytes().timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw TimeoutException('Image read timed out after 30s'),
    );
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
  /// Sets an immediate person count for theme filtering, then fires preprocess
  /// in the background (API is fire-and-forget; must not block capture Continue).
  Future<void> _resolvePersonCountAfterUpload({
    required String sessionId,
    required int clientFaceCount,
  }) async {
    final existingCount = _sessionManager.personCount;
    final immediateCount = resolvePersonCountAfterPreprocess(
      preprocess: null,
      clientFaceCount: clientFaceCount,
      sessionPersonCount: existingCount,
    );
    if (existingCount == null || existingCount <= 0) {
      _sessionManager.setPersonCount(immediateCount);
    }
    WebFlowTrace.log(
      'PREPROCESS',
      'immediate personCount=$immediateCount kIsWeb=$kIsWeb',
    );

    WebFlowTrace.log('PREPROCESS', 'preprocessImage_fire_and_forget');
    unawaited(
      _refinePersonCountFromPreprocess(
        sessionId: sessionId,
        clientFaceCount: clientFaceCount,
        immediateCount: immediateCount,
      ),
    );
  }

  Future<void> _refinePersonCountFromPreprocess({
    required String sessionId,
    required int clientFaceCount,
    required int immediateCount,
  }) async {
    try {
      final preprocess = await _apiService
          .preprocessImage(
            sessionId: sessionId,
            clientFaceCount: clientFaceCount > 0 ? clientFaceCount : null,
          )
          .timeout(AppConstants.kPreprocessTimeout);
      final refined = resolvePersonCountAfterPreprocess(
        preprocess: preprocess,
        clientFaceCount: clientFaceCount,
        sessionPersonCount: immediateCount,
      );
      if (refined != immediateCount) {
        _sessionManager.setPersonCount(refined);
      }
      WebFlowTrace.log(
        'PREPROCESS',
        'background_done personCount=$refined',
      );
    } on TimeoutException catch (e) {
      WebFlowTrace.log(
        'PREPROCESS',
        'background_timeout after ${AppConstants.kPreprocessTimeout.inSeconds}s $e',
      );
    } catch (e) {
      WebFlowTrace.log('PREPROCESS', 'background_ERROR $e');
    }
  }

  /// Called when user taps "Continue" button in Capture Photo screen
  /// Uploads photo, saves client person count, and fires server preprocess in background.
  Future<bool> uploadPhotoToSession({bool uploadAlreadyStarted = false}) async {
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

    final kioskToken = _sessionManager.kioskAuthToken;
    if (kioskToken == null || kioskToken.isEmpty) {
      _errorMessage =
          'Session authentication is missing. Please go back and accept Terms again.';
      notifyListeners();
      return false;
    }

    if (!uploadAlreadyStarted) {
      beginContinueUpload();
    } else if (!_isUploading) {
      beginContinueUpload();
    }

    final sidShort = sessionId.length <= 8 ? sessionId : '${sessionId.substring(0, 8)}…';
    WebFlowTrace.log('UPLOAD', 'begin sessionId=$sidShort kIsWeb=$kIsWeb');

    if (kIsWeb) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }

    try {
      WebFlowTrace.log('UPLOAD', 'ensure_payload_start');
      final base64Image = await _ensureUploadBase64Ready().timeout(
        AppConstants.kSessionUploadTimeout,
        onTimeout: () => throw TimeoutException(
          'Photo preparation timed out after ${AppConstants.kSessionUploadTimeout.inSeconds} seconds',
        ),
      );
      WebFlowTrace.log(
        'UPLOAD',
        'ensure_payload_done dataUrlLen=${base64Image.length}',
      );
      final clientFaceCount = _preparedClientFaceCount ?? 0;

      final payloadChars = base64Image.length;
      final payloadLabel = ImageHelper.formatFileSize(
        (payloadChars * 3 / 4).round(),
      );
      _uploadStatusMessage = 'Uploading photo ($payloadLabel)…';
      notifyListeners();
      ErrorReportingManager.log('📤 Uploading processed image to API');
      WebFlowTrace.log(
        'PATCH',
        'updateSession_photo_start payloadChars=$payloadChars '
        'hasKioskToken=${_sessionManager.kioskAuthToken?.isNotEmpty == true}',
      );

      // PATCH photo + client person count; preprocess returns authoritative count.
      final response = await _apiService.updateSession(
        sessionId: sessionId,
        userImageUrl: base64Image,
        selectedThemeId: null,
        personCount: clientFaceCount > 0 ? clientFaceCount : null,
        framingMetadata: <String, dynamic>{
          'applied': false,
          'mode': 'auto',
          'originalImageUrl': null,
        },
      ).timeout(
        AppConstants.kSessionUploadTimeout,
        onTimeout: () => throw TimeoutException(
          'Upload timed out after ${AppConstants.kSessionUploadTimeout.inSeconds} seconds',
        ),
      );
      WebFlowTrace.log('PATCH', 'updateSession_photo_done');
      
      ErrorReportingManager.log('✅ Image uploaded successfully');
      
      // Save the response to SessionManager
      _sessionManager.setSessionFromResponse(response);
      WebFlowTrace.log('UPLOAD', 'setSessionFromResponse_done');

      await _resolvePersonCountAfterUpload(
        sessionId: sessionId,
        clientFaceCount: clientFaceCount,
      );

      WebFlowTrace.log('UPLOAD', 'success');
      _releaseUploadPayloadMemory();
      return true;
    } on TimeoutException catch (e, st) {
      WebFlowTrace.log('UPLOAD', 'ERROR TimeoutException $e');
      _errorMessage =
          'Upload took too long. Please check your connection and try again.';
      _errorMessage = '$_errorMessage${webUploadErrorHint()}';
      unawaited(
        reportIssue(
          'Photo upload timed out',
          e,
          st,
          extraInfo: {'source': 'photo_capture_upload'},
        ),
      );
      return false;
    } on app_exceptions.ApiException catch (e) {
      WebFlowTrace.log('UPLOAD', 'ERROR ApiException ${e.message}');
      _errorMessage = '${e.message}${webUploadErrorHint(apiError: e)}';
      return false;
    } catch (e, st) {
      WebFlowTrace.log('UPLOAD', 'ERROR $e');
      _errorMessage = 'Failed to upload photo: ${e.toString()}';
      _errorMessage = '$_errorMessage${webUploadErrorHint()}';
      unawaited(
        reportIssue(
          'Photo upload failed',
          e,
          st,
          extraInfo: {'source': 'photo_capture_upload'},
        ),
      );
      return false;
    } finally {
      _stopUploadTimer();
      _isUploading = false;
      _uploadStatusMessage = null;
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

    if (kIsWeb) {
      final kioskToken = _sessionManager.kioskAuthToken;
      if (kioskToken == null || kioskToken.isEmpty) {
        _errorMessage =
            'Session authentication is missing. Please return to Terms and start again.';
        notifyListeners();
        return false;
      }
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
    } on TimeoutException catch (e, st) {
      _errorMessage = 'Request took too long. Please check your connection and try again.';
      unawaited(
        reportIssue(
          'Update session timed out',
          e,
          st,
          extraInfo: {'source': 'photo_capture_update_session'},
        ),
      );
      return false;
    } on app_exceptions.ApiException catch (e) {
      _errorMessage = e.message;
      return false;
    } catch (e, st) {
      _errorMessage = 'Failed to update session: ${e.toString()}';
      unawaited(
        reportIssue(
          'Failed to update session',
          e,
          st,
          extraInfo: {'source': 'photo_capture_update_session'},
        ),
      );
      return false;
    } finally {
      _isUploading = false;
      notifyListeners();
    }
  }

  /// Eagerly releases camera native buffers. Call before navigating away
  /// so the next screen doesn't overlap with camera heap on low-RAM devices.
  Future<void> disposeCamera() async {
    final ctrl = _cameraController;
    _cameraController = null;
    _nativeCameraDetails = null;
    if (ctrl == null) return;
    try {
      ctrl.removeListener(_onCameraControllerUpdate);
      await ctrl.dispose();
    } catch (e, st) {
      AppLogger.error('disposeCamera failed', error: e, stackTrace: st);
    }
  }

  /// Disposes the camera controller
  @override
  void dispose() {
    _disposed = true;
    _countdownGeneration++;
    _countdownValue = null;
    _stopUploadTimer();
    _releaseUploadPayloadMemory();
    unawaited(_captureSoundService.dispose());
    unawaited(disposeCamera());
    super.dispose();
  }
}

