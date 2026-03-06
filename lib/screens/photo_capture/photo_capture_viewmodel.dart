import 'dart:async';
import 'package:flutter/foundation.dart' show ChangeNotifier, TargetPlatform, compute, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart' show DeviceOrientation, MethodChannel;
import 'package:camera/camera.dart';
import 'package:camera/camera.dart' as cam show availableCameras;
import 'package:flutter/material.dart' show debugPrint;
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'photo_model.dart';
import '../../services/api_service.dart';
import '../../services/session_manager.dart';
import '../../utils/constants.dart';
import '../../utils/device_classifier.dart';
import '../../utils/app_device_type.dart';
import '../../utils/exceptions.dart' as app_exceptions;
import '../../utils/image_helper.dart';
import '../../utils/logger.dart';
import '../../services/error_reporting/error_reporting_manager.dart';

class CaptureViewModel extends ChangeNotifier {
  final ApiService _apiService;
  final SessionManager _sessionManager;
  final Uuid _uuid = const Uuid();
  static List<CameraDescription>? _cachedAvailableCameras;
  CameraController? _cameraController;
  PhotoModel? _capturedPhoto;
  List<CameraDescription> _availableCameras = [];
  CameraDescription? _currentCamera;
  AppDeviceType? _deviceType;
  bool _isLoadingCameras = false;
  bool _isInitializing = false;
  bool _isCapturing = false;
  bool _isSelectingFromGallery = false;
  bool _isUploading = false;
  String? _errorMessage;
  
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
  set capturedPhoto(PhotoModel? photo) {
    _capturedPhoto = photo;
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
    } catch (_) {}
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
    } catch (_) {}
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

  /// Picks the default camera: prefer real external (UUID/by name), then by direction, then first.
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
    // 2) Then by lensDirection.external
    final byDirection = cameras.where(
      (c) => c.lensDirection == CameraLensDirection.external,
    ).toList();
    if (byDirection.isNotEmpty) {
      return byDirection.first;
    }
    return cameras.first;
  }

  /// True if camera name looks like a real external device (e.g. iOS UUID).
  /// Excludes built-in cameras whose names contain "built-in" (plugin can misreport direction).
  bool _looksLikeExternalCameraName(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('built-in')) return false;
    if (name.length < 10) return false;
    // iOS external cameras use UUID format (e.g. 00000000-0010-0000-03F0-000007600000)
    if (name.length > 30 && name.contains('-')) return true;
    return lower.contains('webcam') || lower.contains('usb') || lower.contains('external');
  }

  /// Set device type from UI (from [DeviceClassifier.getDeviceType]).
  /// Used to filter cameras: tablet/TV → external only, phone → built-in only.
  void setDeviceType(AppDeviceType? type) {
    _deviceType = type;
    unawaited(_applyDefaultPreviewRotationForDevice());
  }

  Future<void> _applyDefaultPreviewRotationForDevice() async {
    if (_isPreviewRotationConfiguredByUser) return;
    if (!shouldUseLandscapePreviewRotationWorkaround) return;

    final desiredRotation = _displayRotation == 0
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

  /// Loads available cameras when user opens Capture screen.
  /// On Android, availableCameras() returns an empty list (no exception) when
  /// camera permission is not granted, so we must request permission first.
  /// On iOS, the camera plugin triggers the permission dialog itself.
  Future<void> loadCameras({bool forceRefresh = false}) async {
    _isLoadingCameras = true;
    _errorMessage = null;
    notifyListeners();

    try {
      if (!forceRefresh && _cachedAvailableCameras != null) {
        _availableCameras = _externalCamerasFirst(_cachedAvailableCameras!);
        if (_currentCamera == null && _availableCameras.isNotEmpty) {
          _currentCamera = _pickDefaultCamera(_availableCameras);
        }
        notifyListeners();
        return;
      }

      // On Android, request camera permission before enumeration.
      // Without this, availableCameras() silently returns an empty list.
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        final status = await Permission.camera.status;
        if (!status.isGranted) {
          AppLogger.debug('📷 Camera permission not granted, requesting...');
          final result = await Permission.camera.request();
          AppLogger.debug('📷 Permission result: $result');
          if (!result.isGranted) {
            _errorMessage = 'Camera permission is required to detect and use cameras.';
            _isLoadingCameras = false;
            notifyListeners();
            return;
          }
        }
      }

      final allCameras = await cam.availableCameras();

      if (allCameras.isEmpty) {
        ErrorReportingManager.log('❌ Camera enumeration returned 0 cameras');
        await ErrorReportingManager.recordError(
          Exception('Camera enumeration returned 0 cameras'),
          StackTrace.current,
          reason: 'No cameras detected',
          extraInfo: {
            'platform': defaultTargetPlatform.name,
            'message': 'availableCameras() returned empty list; no exception thrown',
          },
          fatal: false,
        );
      }
      AppLogger.debug('📷 Detected ${allCameras.length} camera(s):');
      for (final c in allCameras) {
        AppLogger.debug('  - Name: "${c.name}", Direction: ${c.lensDirection}');
      }
      // Show all cameras (no device-type filter that could hide the only camera)
      _availableCameras = _externalCamerasFirst(allCameras);
      _cachedAvailableCameras = List<CameraDescription>.from(allCameras);

      AppLogger.debug(
          '📋 CaptureViewModel.loadCameras - Device: $_deviceType, showing ${_availableCameras.length} camera(s):');
      for (var i = 0; i < _availableCameras.length; i++) {
        final c = _availableCameras[i];
        final ext = c.lensDirection == CameraLensDirection.external || _looksLikeExternalCameraName(c.name);
        AppLogger.debug('   ${i + 1}. ${c.name} (${c.lensDirection}) ${ext ? "[external]" : "[built-in]"}');
      }

      // If no camera is currently selected and cameras are available, prefer external then first
      if (_currentCamera == null && _availableCameras.isNotEmpty) {
        _currentCamera = _pickDefaultCamera(_availableCameras);
        final isExt = _currentCamera!.lensDirection == CameraLensDirection.external || _looksLikeExternalCameraName(_currentCamera!.name);
        AppLogger.debug('📷 Auto-selected camera: ${_currentCamera!.name} (${_currentCamera!.lensDirection}) ${isExt ? "[external]" : "[built-in]"}');
      }

      notifyListeners();
    } catch (e, stackTrace) {
      _errorMessage = 'Failed to load cameras: $e';
      ErrorReportingManager.log('❌ Failed to load cameras: $e');
      await ErrorReportingManager.recordError(
        e,
        stackTrace,
        reason: 'loadCameras failed (exception from camera plugin or availableCameras)',
        extraInfo: {
          'error': e.toString(),
          'errorType': e.runtimeType.toString(),
        },
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
    
    // Dispose current camera controller
    if (_cameraController != null) {
      AppLogger.debug('   Disposing current camera controller...');
      try {
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
          final isExt = _currentCamera!.lensDirection == CameraLensDirection.external || _looksLikeExternalCameraName(_currentCamera!.name);
          AppLogger.debug('📷 Selected camera: ${_currentCamera!.name} (${_currentCamera!.lensDirection}) ${isExt ? "[external]" : "[built-in]"}');
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

  /// Initializes the camera with the selected camera
  Future<void> initializeCamera(CameraDescription camera) async {
    _isInitializing = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _minZoom = null;
      _maxZoom = null;
      _currentZoom = 1.0;

      // CRITICAL: Fully release the previous camera before opening the new one
      final hadController = _cameraController != null;
      if (_cameraController != null) {
        AppLogger.debug('🔄 Disposing existing camera controller before switch...');
        try {
          await _cameraController!.dispose();
        } catch (e) {
          AppLogger.debug('   ⚠️ Warning: Error disposing existing controller: $e');
        }
        _cameraController = null;
      }
      // Brief delay only when we actually released a camera (lets system free resources)
      if (hadController) {
        await Future.delayed(const Duration(milliseconds: 100));
      }

      // Debug: Log which camera is being initialized
      AppLogger.debug('📸 CaptureViewModel.initializeCamera called:');
      AppLogger.debug('   Camera name: ${camera.name}');
      AppLogger.debug('   Camera direction: ${camera.lensDirection}');
      AppLogger.debug('   Camera sensor orientation: ${camera.sensorOrientation}');
      
      // Set error reporting context for better error tracking
      unawaited(ErrorReportingManager.setCameraContext(
        cameraId: camera.name,
        cameraDirection: camera.lensDirection.toString(),
        isExternal: camera.lensDirection == CameraLensDirection.external,
      ));
      ErrorReportingManager.log('Initializing camera: ${camera.name}');
      
      CameraDescription cameraToUse = camera;
      try {
        cameraToUse = _availableCameras.firstWhere((c) => c.name == camera.name);
      } catch (_) {}
      final isExternalCamera =
          cameraToUse.lensDirection == CameraLensDirection.external ||
          _looksLikeExternalCameraName(cameraToUse.name);
      final resolutionPreset = isExternalCamera
          ? ResolutionPreset.high
          : ResolutionPreset.high;
      _cameraController = CameraController(
        cameraToUse,
        resolutionPreset,
        enableAudio: false,
      );
      await _cameraController!.initialize().timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw Exception('Camera initialization timed out after 15 seconds'),
      );

      if (_cameraController != null) {
        final activeCamera = _cameraController!.description;
        AppLogger.debug('✅ CaptureViewModel - Camera controller obtained:');
        AppLogger.debug('   Active camera name: ${activeCamera.name}');
        AppLogger.debug('   Active camera direction: ${activeCamera.lensDirection}');

        _currentCamera = camera;
        _minZoom = null;
        _maxZoom = null;
        _currentZoom = 1.0;

        _isInitializing = false;
        _errorMessage = null;
        notifyListeners();
        unawaited(_finishCameraSetup(camera));
        return;
      }

      AppLogger.debug('❌ ERROR: Camera controller is null after initialization!');
      _errorMessage = 'Camera controller is null after initialization';
      _isInitializing = false;
      notifyListeners();
    } on app_exceptions.PermissionException catch (e, stackTrace) {
      _errorMessage = e.message;
      
      // Log to Bugsnag
      ErrorReportingManager.log('❌ Permission exception during camera initialization');
      await ErrorReportingManager.recordError(
        e,
        stackTrace,
        reason: 'Permission exception',
        extraInfo: {
          'message': e.message,
          'camera_name': camera.name,
        },
      );
      
      notifyListeners();
    } on app_exceptions.CameraException catch (e, stackTrace) {
      _errorMessage = e.message;
      
      // Log to Bugsnag
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
      
      notifyListeners();
    } catch (e, stackTrace) {
      _errorMessage = 'Failed to initialize camera: $e';
      
      // Log to Bugsnag
      ErrorReportingManager.log('❌ Unexpected error during camera initialization');
      await ErrorReportingManager.recordError(
        e,
        stackTrace,
        reason: 'Unexpected camera initialization error',
        extraInfo: {
          'error': e.toString(),
          'camera_name': camera.name,
        },
      );
      
      notifyListeners();
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  Future<void> _finishCameraSetup(CameraDescription camera) async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;

    try {
      final rotation = await _fetchDisplayRotation();
      _displayRotation = rotation;
      AppLogger.debug('   Display rotation: $rotation');

      // Best-effort capture lock for cameras that report 0/180 sensor orientation.
      if (!kIsWeb &&
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
  }

  /// Loads zoom range in background with timeout so init never hangs.
  Future<void> _loadZoomInBackground() async {
    final ctrl = _cameraController;
    if (ctrl == null || !ctrl.value.isInitialized) return;

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
      final defaultZoom = 1.0.clamp(minZ, maxZ);
      await ctrl.setZoomLevel(defaultZoom);
    } on CameraException {
      // Zoom not supported
    } on TimeoutException {
      debugPrint('Zoom level load timed out');
    } catch (_) {}
    _minZoom = minZ;
    _maxZoom = maxZ;
    if (minZ != null && maxZ != null) {
      _currentZoom = 1.0.clamp(minZ, maxZ);
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
      debugPrint('setZoomLevel failed: $e');
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
        return;
      }
      
      if (_countdownValue! > 1) {
        _countdownValue = _countdownValue! - 1;
        notifyListeners();
      } else {
        // Countdown finished, capture the photo
        timer.cancel();
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

  /// Captures a photo
  Future<void> capturePhoto() async {
    AppLogger.debug('📸 capturePhoto() called');
    AppLogger.debug('   isReady: $isReady');

    ErrorReportingManager.log('📸 Photo capture attempt started');
    await ErrorReportingManager.setCustomKeys({
      'capture_isReady': isReady,
      'capture_hasController': _cameraController != null,
      'capture_initialized': _cameraController?.value.isInitialized ?? false,
    });

    if (!isReady) {
      String debugInfo = 'Camera not ready.\n\n';
      debugInfo += 'Debug Info:\n';
      debugInfo += '- Controller Exists: ${_cameraController != null}\n';
      if (_cameraController != null) {
        debugInfo += '- Controller Initialized: ${_cameraController!.value.isInitialized}\n';
      }

      _errorMessage = debugInfo;
      AppLogger.debug('❌ Camera not ready, cannot capture photo');
      
      // Log to error reporting
      ErrorReportingManager.log('❌ Camera not ready for capture');
      await ErrorReportingManager.recordError(
        Exception('Camera not ready for photo capture'),
        StackTrace.current,
        reason: 'Camera not ready',
        extraInfo: {'debug_info': debugInfo},
      );
      
      notifyListeners();
      return;
    }

    _isCapturing = true;
    _errorMessage = null;
    notifyListeners();

    try {
      AppLogger.debug('📸 Capturing photo...');
      ErrorReportingManager.log('📸 Photo capture started');
      final XFile imageFile = await _cameraController!.takePicture();
      ErrorReportingManager.log('✅ Photo captured');
      AppLogger.debug('✅ Photo captured successfully');

      // Use raw capture at very high quality (no resize/normalize)
      AppLogger.debug('✅ Photo captured (raw, very high quality)');

      // Get camera ID from either standard controller or current camera
      final cameraId = _cameraController?.description.name ?? _currentCamera?.name;
      final photoId = _uuid.v4();
      _capturedPhoto = PhotoModel(
        id: photoId,
        imageFile: imageFile,
        capturedAt: DateTime.now(),
        cameraId: cameraId,
      );
      
      // Track successful photo capture
      await ErrorReportingManager.setPhotoCaptureContext(
        photoId: photoId,
        sessionId: _sessionManager.sessionId,
      );
      ErrorReportingManager.log('Photo captured successfully: $photoId');
      
      notifyListeners();
    } on CameraException catch (e, stackTrace) {
      final errorString = e.toString();
      final isCameraClosedError = errorString.contains('Camera is closed') ||
          errorString.contains('camera is closed') ||
          errorString.contains('CameraDeviceImpl.close');
      ErrorReportingManager.log('❌ takePicture failed');
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
      _errorMessage = 'Camera Error:\n${e.toString()}';
      notifyListeners();
    } catch (e, stackTrace) {
      // Check if this is a timeout exception
      final isTimeout = e.toString().contains('TimeoutException') || 
                        e.toString().contains('timed out') ||
                        e.toString().contains('CAPTURE_TIMEOUT');
      
      _errorMessage = 'Capture Failed:\n$e';
      
      // Log to error reporting with extra details for timeouts
      if (isTimeout) {
        ErrorReportingManager.log('⏱️ TIMEOUT during photo capture');
        await ErrorReportingManager.setCustomKeys({
          'timeout_occurred': true,
          'timeout_error': e.toString(),
        });
      } else {
        ErrorReportingManager.log('❌ Unexpected error during photo capture: $e');
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
        imageQuality: 95,
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
      
      _capturedPhoto = PhotoModel(
        id: photoId,
        imageFile: normalizedFile,
        capturedAt: DateTime.now(),
        cameraId: cameraId,
      );
      
      // Track successful photo selection
      await ErrorReportingManager.setPhotoCaptureContext(
        photoId: photoId,
        sessionId: _sessionManager.sessionId,
      );
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
    _capturedPhoto = null;
    _errorMessage = null;
    notifyListeners();
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

    try {
      // Get the image file from the captured photo
      final imageFile = _capturedPhoto!.imageFile;
      
      ErrorReportingManager.log('📦 Encoding image for upload (no resize; already normalized at capture)');
      
      // Encode to base64 in background isolate. No resize: image is already
      // 1920px max / 85% JPEG from capture (custom plugin or Flutter normalization).
      final base64Image = await compute(
        _encodeImageInBackground,
        imageFile.path,
      );
      
      ErrorReportingManager.log('✅ Image encoded for upload');
      ErrorReportingManager.log('📤 Uploading processed image to API');
      
      // Step 3: Update session with photo (PATCH /api/sessions/{sessionId})
      // Note: selectedThemeId is not included here - it will be set later in theme selection
      // Use 60s timeout so UI cannot hang (upload can be slow for large images)
      const uploadTimeout = Duration(seconds: 60);
      final response = await _apiService.updateSession(
        sessionId: sessionId,
        userImageUrl: base64Image,
        selectedThemeId: null, // Theme will be selected later
      ).timeout(
        uploadTimeout,
        onTimeout: () => throw TimeoutException(
          'Upload timed out after ${uploadTimeout.inSeconds} seconds',
        ),
      );
      
      ErrorReportingManager.log('✅ Image uploaded successfully');
      
      // Save the response to SessionManager
      _sessionManager.setSessionFromResponse(response);
      
      // Step 3b: Preprocess image in background (fire-and-forget)
      // This runs validation, compression, and person detection ahead of time
      // Don't wait for it to complete - it's an optimization
      ErrorReportingManager.log('🔄 Triggering background image preprocessing');
      _apiService.preprocessImage(sessionId: sessionId);
      
      return true;
    } on TimeoutException {
      _errorMessage = 'Upload took too long. Please check your connection and try again.';
      return false;
    } on app_exceptions.ApiException catch (e) {
      _errorMessage = e.message;
      return false;
    } catch (e) {
      _errorMessage = 'Failed to upload photo: ${e.toString()}';
      return false;
    } finally {
      _stopUploadTimer();
      _isUploading = false;
      notifyListeners();
    }
  }

  /// Encodes image file to base64 data URL for upload. No resize: dimensions
  /// and size are already enforced at capture (custom plugin or Flutter normalization).
  static Future<String> _encodeImageInBackground(String imagePath) async {
    final file = XFile(imagePath);
    return await ImageHelper.encodeImageToBase64(file);
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
      
      // Encode to base64 in background (no resize; already normalized at capture)
      final base64Image = await compute(
        _encodeImageInBackground,
        imageFile.path,
      );
      
      // Update session via API: PATCH /api/sessions/{sessionId}
      const updateTimeout = Duration(seconds: 60);
      final response = await _apiService.updateSession(
        sessionId: sessionId,
        userImageUrl: base64Image,
        selectedThemeId: selectedThemeId,
      ).timeout(
        updateTimeout,
        onTimeout: () => throw TimeoutException(
          'Update timed out after ${updateTimeout.inSeconds} seconds',
        ),
      );
      
      // Save the response to SessionManager
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

  /// Disposes the camera controller
  @override
  void dispose() {
    _stopUploadTimer();
    _cameraController?.dispose();
    _cameraController = null;
    super.dispose();
  }
}

