import 'dart:async';
import 'package:flutter/foundation.dart' show ChangeNotifier, compute;
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'photo_model.dart';
import '../../services/camera_service.dart';
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
  final CameraService _cameraService;
  final ApiService _apiService;
  final SessionManager _sessionManager;
  final Uuid _uuid = const Uuid();
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

  CaptureViewModel({
    CameraService? cameraService,
    ApiService? apiService,
    SessionManager? sessionManager,
  })  : _cameraService = cameraService ?? CameraService(),
        _apiService = apiService ?? ApiService(),
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
    // Check if using custom controller
    if (_cameraService.isUsingCustomController) {
      return _cameraService.customController?.isPreviewRunning ?? false;
    }
    // Check standard controller
    return _cameraController != null &&
        _cameraController!.value.isInitialized;
  }
  
  CameraService get cameraService => _cameraService;

  /// Picks the default camera: prefer externally connected, otherwise first available (e.g. built-in).
  /// External is detected by lensDirection.external or by name (iOS external cameras use UUID as name).
  CameraDescription _pickDefaultCamera(List<CameraDescription> cameras) {
    if (cameras.isEmpty) {
      throw StateError('No cameras available');
    }
    // 1) Prefer by lensDirection.external (set by camera service for external/USB cameras)
    final byDirection = cameras.where(
      (c) => c.lensDirection == CameraLensDirection.external,
    ).toList();
    if (byDirection.isNotEmpty) {
      return byDirection.first;
    }
    // 2) Fallback: on iOS, external cameras use UUID as name (e.g. 00000000-0010-0000-03F0-000007600000)
    final byName = cameras.where((c) => _looksLikeExternalCameraName(c.name)).toList();
    if (byName.isNotEmpty) {
      return byName.first;
    }
    return cameras.first;
  }

  /// True if camera name looks like an external device (e.g. iOS UUID, or contains "webcam"/"usb").
  bool _looksLikeExternalCameraName(String name) {
    if (name.length < 10) return false;
    // iOS external cameras use UUID format
    if (name.length > 30 && name.contains('-')) return true;
    final lower = name.toLowerCase();
    return lower.contains('webcam') || lower.contains('usb') || lower.contains('external');
  }

  /// Set device type from UI (from [DeviceClassifier.getDeviceType]).
  /// Used to filter cameras: tablet/TV → external only, phone → built-in only.
  void setDeviceType(AppDeviceType? type) {
    _deviceType = type;
  }

  /// Sync tablet/TV flag from UI (e.g. MediaQuery) so initial load doesn't block on async device detection.
  bool _isTabletOrTv = false;
  void setTabletOrTv(bool isTabletOrTv) {
    _isTabletOrTv = isTabletOrTv;
  }

  /// Filter cameras by device type: tablet/TV show only external; phone show only built-in.
  /// When [_deviceType] is null, uses [_isTabletOrTv] so we can filter without waiting for getDeviceType().
  /// When the filtered list is empty, returns all cameras so the user always has at least one.
  List<CameraDescription> _filterCamerasByDeviceType(List<CameraDescription> cameras) {
    if (cameras.isEmpty) return cameras;
    final bool onlyExternal = _deviceType != null
        ? DeviceClassifier.showOnlyExternalCameras(_deviceType!)
        : _isTabletOrTv;
    final filtered = onlyExternal
        ? cameras
            .where((c) =>
                c.lensDirection == CameraLensDirection.external ||
                _looksLikeExternalCameraName(c.name))
            .toList()
        : cameras
            .where((c) =>
                c.lensDirection != CameraLensDirection.external &&
                !_looksLikeExternalCameraName(c.name))
            .toList();
    if (filtered.isEmpty) return cameras;
    return filtered;
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

  /// Loads available cameras
  Future<void> loadCameras() async {
    _isLoadingCameras = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final allCameras = await _cameraService.getAvailableCameras();
      _availableCameras = _filterCamerasByDeviceType(allCameras);
      _availableCameras = _externalCamerasFirst(_availableCameras);

      // Always print to console for debugging
      print('📷 [Cameras] Device type: $_deviceType');
      print('📷 [Cameras] Detected ${allCameras.length} total, showing ${_availableCameras.length} after filter:');
      for (var i = 0; i < _availableCameras.length; i++) {
        final c = _availableCameras[i];
        final ext = c.lensDirection == CameraLensDirection.external || _looksLikeExternalCameraName(c.name);
        print('   ${i + 1}. name="${c.name}" direction=${c.lensDirection} ${ext ? "[external]" : "[built-in]"}');
      }

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
        print('📷 [Cameras] Auto-selected: ${_currentCamera!.name} (${_currentCamera!.lensDirection}) ${isExt ? "[external]" : "[built-in]"}');
        AppLogger.debug('📷 Auto-selected camera: ${_currentCamera!.name} (${_currentCamera!.lensDirection}) ${isExt ? "[external]" : "[built-in]"}');
      }

      notifyListeners();
    } catch (e, stackTrace) {
      _errorMessage = 'Failed to load cameras: $e';
      
      // Log to Bugsnag
      ErrorReportingManager.log('❌ Failed to load cameras');
      await ErrorReportingManager.recordError(
        e,
        stackTrace,
        reason: 'Failed to load available cameras',
        extraInfo: {
          'error': e.toString(),
        },
      );
      
      notifyListeners();
    } finally {
      _isLoadingCameras = false;
      notifyListeners();
    }
  }

  /// Resets the camera screen and initializes with the first available camera
  /// This is a common function used both when entering the screen and when reloading
  Future<void> resetAndInitializeCameras() async {
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
        _cameraController = null;
      } catch (e, stackTrace) {
          AppLogger.debug('   ⚠️ Warning: Error disposing camera: $e');
          
          // Log to Bugsnag (non-fatal)
          ErrorReportingManager.log('⚠️ Warning: Error disposing camera controller');
          await ErrorReportingManager.recordError(
            e,
            stackTrace,
            reason: 'Error disposing camera controller during reset',
            extraInfo: {
              'error': e.toString(),
            },
            fatal: false,
          );
      }
    }
    
    // Also dispose custom controller if exists
    if (_cameraService.isUsingCustomController) {
      try {
        await _cameraService.customController?.dispose();
      } catch (e, stackTrace) {
          AppLogger.debug('   ⚠️ Warning: Error disposing custom controller: $e');
          
          // Log to Bugsnag (non-fatal)
          ErrorReportingManager.log('⚠️ Warning: Error disposing custom controller');
          await ErrorReportingManager.recordError(
            e,
            stackTrace,
            reason: 'Error disposing custom controller during reset',
            extraInfo: {
              'error': e.toString(),
            },
            fatal: false,
          );
      }
    }
    
    // Clear current camera selection
    _currentCamera = null;
    
    // Clear any previous errors
    _errorMessage = null;
    
    // Reload cameras
    await loadCameras();
    
    // Select and initialize default camera (prefer external, else first)
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
      // CRITICAL: Fully release the previous camera before opening the new one
      if (_cameraController != null) {
        AppLogger.debug('🔄 Disposing existing camera controller before switch...');
        try {
          await _cameraController!.dispose();
        } catch (e) {
          AppLogger.debug('   ⚠️ Warning: Error disposing existing controller: $e');
        }
        _cameraController = null;
      }
      await _cameraService.dispose();
      await Future.delayed(const Duration(milliseconds: 300));

      // Debug: Log which camera is being initialized
      AppLogger.debug('📸 CaptureViewModel.initializeCamera called:');
      AppLogger.debug('   Camera name: ${camera.name}');
      AppLogger.debug('   Camera direction: ${camera.lensDirection}');
      AppLogger.debug('   Camera sensor orientation: ${camera.sensorOrientation}');
      
      // Set error reporting context for better error tracking
      await ErrorReportingManager.setCameraContext(
        cameraId: camera.name,
        cameraDirection: camera.lensDirection.toString(),
        isExternal: camera.lensDirection == CameraLensDirection.external,
      );
      ErrorReportingManager.log('Initializing camera: ${camera.name}');
      
      // Use the camera directly
      final cameraToUse = camera;
      
      await _cameraService.initializeCamera(cameraToUse);
      
      // Check if using custom controller (for external cameras)
      if (_cameraService.isUsingCustomController) {
        final customController = _cameraService.customController;
        if (customController != null) {
          AppLogger.debug('✅ CaptureViewModel - Custom camera controller obtained');
          AppLogger.debug('   Device ID: ${customController.currentDeviceId}');
          AppLogger.debug('   Texture ID: ${customController.textureId}');
          
          // Start preview with error handling
          try {
            await customController.startPreview();
            AppLogger.debug('✅ Preview started for custom controller');
            
            // Small delay to ensure preview is fully running before allowing capture
            await Future.delayed(const Duration(milliseconds: 500));
            AppLogger.debug('✅ Preview stabilization delay complete');
          } catch (e, stackTrace) {
            AppLogger.debug('❌ ERROR: Failed to start preview: $e');
            _errorMessage = 'Failed to start camera preview: $e';
            
            // Log to Bugsnag
            ErrorReportingManager.log('❌ Failed to start camera preview');
            await ErrorReportingManager.recordError(
              e,
              stackTrace,
              reason: 'Failed to start preview for custom controller',
              extraInfo: {
                'camera_name': camera.name,
                'camera_direction': camera.lensDirection.toString(),
                'device_id': customController.currentDeviceId ?? 'unknown',
                'error': e.toString(),
              },
            );
            
            _isInitializing = false;
            notifyListeners();
            return;
          }
          
          _currentCamera = camera;
          _isInitializing = false;
          _errorMessage = null;
          notifyListeners(); // CRITICAL: Notify listeners so UI rebuilds with new preview
          return; // CRITICAL: Return to avoid calling notifyListeners() again
        } else {
          AppLogger.debug('❌ ERROR: Custom controller is null after initialization!');
          _errorMessage = 'Custom camera controller is null after initialization';
          _isInitializing = false;
          notifyListeners();
          return;
        }
      } else {
        // Standard controller
        _cameraController = _cameraService.controller;
        
        // Debug: Verify which camera was actually initialized
        if (_cameraController != null) {
          final activeCamera = _cameraController!.description;
          AppLogger.debug('✅ CaptureViewModel - Camera controller obtained:');
          AppLogger.debug('   Active camera name: ${activeCamera.name}');
          AppLogger.debug('   Active camera direction: ${activeCamera.lensDirection}');
          AppLogger.debug('   Active camera sensor orientation: ${activeCamera.sensorOrientation}');
          
          // Verify it's the correct camera - check both name AND lensDirection
          // External cameras on iPadOS should report CameraLensDirection.external
          final nameMatches = activeCamera.name == cameraToUse.name;
          final directionMatches = activeCamera.lensDirection == cameraToUse.lensDirection;
          
          if (!nameMatches || !directionMatches) {
            AppLogger.debug('❌ ERROR: Wrong camera is active!');
            AppLogger.debug('   Expected name: ${cameraToUse.name}');
            AppLogger.debug('   Got name: ${activeCamera.name}');
            AppLogger.debug('   Expected direction: ${cameraToUse.lensDirection}');
            AppLogger.debug('   Got direction: ${activeCamera.lensDirection}');
            _errorMessage = 'Wrong camera initialized. Expected ${cameraToUse.name} (${cameraToUse.lensDirection}), but got ${activeCamera.name} (${activeCamera.lensDirection}).';
            _isInitializing = false;
            notifyListeners();
            return;
          }
          
          AppLogger.debug('✅ Camera verification passed in CaptureViewModel');
          AppLogger.debug('   ✅ Active direction: ${activeCamera.lensDirection}');
          _currentCamera = camera;
          _isInitializing = false;
          _errorMessage = null;
          notifyListeners();
          return; // CRITICAL: Return to avoid calling notifyListeners() again in finally block
        } else {
          AppLogger.debug('❌ ERROR: Camera controller is null after initialization!');
          _errorMessage = 'Camera controller is null after initialization';
          _isInitializing = false;
          notifyListeners();
          return;
        }
      }
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
    AppLogger.debug('   isUsingCustomController: ${_cameraService.isUsingCustomController}');
    if (_cameraService.isUsingCustomController) {
      AppLogger.debug('   customController: ${_cameraService.customController != null}');
      AppLogger.debug('   isPreviewRunning: ${_cameraService.customController?.isPreviewRunning}');
    }
    
    // Log to error reporting
    ErrorReportingManager.log('📸 Photo capture attempt started');
    await ErrorReportingManager.setCustomKeys({
      'capture_isReady': isReady,
      'capture_useCustomController': _cameraService.isUsingCustomController,
      'capture_hasCustomController': _cameraService.customController != null,
      'capture_isPreviewRunning': _cameraService.customController?.isPreviewRunning ?? false,
      'capture_deviceId': _cameraService.customController?.currentDeviceId ?? 'none',
      'capture_textureId': _cameraService.customController?.textureId ?? -1,
    });
    
    // Detailed error message for debugging
    if (!isReady) {
      String debugInfo = 'Camera not ready.\n\n';
      debugInfo += 'Debug Info:\n';
      debugInfo += '- Using Custom Controller: ${_cameraService.isUsingCustomController}\n';
      
      if (_cameraService.isUsingCustomController) {
        debugInfo += '- Custom Controller Exists: ${_cameraService.customController != null}\n';
        if (_cameraService.customController != null) {
          debugInfo += '- Preview Running: ${_cameraService.customController!.isPreviewRunning}\n';
          debugInfo += '- Initialized: ${_cameraService.customController!.isInitialized}\n';
          debugInfo += '- Device ID: ${_cameraService.customController!.currentDeviceId}\n';
          debugInfo += '- Texture ID: ${_cameraService.customController!.textureId}\n';
        }
      } else {
        debugInfo += '- Standard Controller Exists: ${_cameraController != null}\n';
        if (_cameraController != null) {
          debugInfo += '- Controller Initialized: ${_cameraController!.value.isInitialized}\n';
        }
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
      AppLogger.debug('📸 Calling _cameraService.takePicture()...');
      final rawImageFile = await _cameraService.takePicture();
      AppLogger.debug('✅ Photo captured successfully');

      // Custom plugin already normalizes at capture (native); standard Flutter camera plugin
      // cannot be modified, so we normalize here only when using the standard plugin.
      final XFile imageFile = _cameraService.isUsingCustomController
          ? rawImageFile
          : await ImageHelper.normalizeAndSaveCapturedPhoto(rawImageFile);
      if (!_cameraService.isUsingCustomController) {
        AppLogger.debug('✅ Photo normalized to standard format (standard camera path)');
      }

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
    } on app_exceptions.CameraException catch (e, stackTrace) {
      _errorMessage = 'Camera Error:\n${e.message}';
      
      // Log to error reporting
      ErrorReportingManager.log('❌ CameraException during photo capture: ${e.message}');
      await ErrorReportingManager.recordError(
        e,
        stackTrace,
        reason: 'CameraException during photo capture',
        extraInfo: {
          'message': e.message,
          'camera': _currentCamera?.name ?? 'unknown',
          'custom_controller': _cameraService.isUsingCustomController,
        },
      );
      
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
          'custom_controller': _cameraService.isUsingCustomController,
          'preview_running': _cameraService.customController?.isPreviewRunning ?? false,
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
    _cameraService.dispose();
    _cameraController = null;
    super.dispose();
  }
}

