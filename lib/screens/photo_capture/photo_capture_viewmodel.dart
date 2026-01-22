import 'package:flutter/foundation.dart' show ChangeNotifier, kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:camera/camera.dart';
import 'package:uuid/uuid.dart';
import 'photo_model.dart';
import '../../services/camera_service.dart';
import '../../services/api_service.dart';
import '../../services/session_manager.dart';
import '../../utils/exceptions.dart' as app_exceptions;
import '../../utils/image_helper.dart';
import '../../utils/logger.dart';
import '../../utils/crashlytics_helper.dart';

/// Helper function to check if running on iOS
bool get _isIOS {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.iOS;
}

class CaptureViewModel extends ChangeNotifier {
  final CameraService _cameraService;
  final ApiService _apiService;
  final SessionManager _sessionManager;
  final Uuid _uuid = const Uuid();
  CameraController? _cameraController;
  PhotoModel? _capturedPhoto;
  List<CameraDescription> _availableCameras = [];
  CameraDescription? _currentCamera;
  bool _isLoadingCameras = false;
  bool _isInitializing = false;
  bool _isCapturing = false;
  bool _isUploading = false;
  String? _errorMessage;

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
  bool get isUploading => _isUploading;
  String? get errorMessage => _errorMessage;
  bool get hasError => _errorMessage != null;
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

  /// Loads available cameras
  Future<void> loadCameras() async {
    _isLoadingCameras = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _availableCameras = await _cameraService.getAvailableCameras();
      
      AppLogger.debug('📋 CaptureViewModel.loadCameras - Found ${_availableCameras.length} cameras:');
      for (var camera in _availableCameras) {
        AppLogger.debug('   - ${camera.name} (Direction: ${camera.lensDirection})');
      }
      
      // If no camera is currently selected and cameras are available, select the first one
      if (_currentCamera == null && _availableCameras.isNotEmpty) {
        _currentCamera = _availableCameras.first;
        AppLogger.debug('📷 Auto-selected first camera: ${_currentCamera!.name}');
      }
      
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to load cameras: $e';
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
    
    // Clear any captured photo
    _capturedPhoto = null;
    
    // Dispose current camera controller
    if (_cameraController != null) {
        AppLogger.debug('   Disposing current camera controller...');
      try {
        await _cameraController!.dispose();
        _cameraController = null;
      } catch (e) {
          AppLogger.debug('   ⚠️ Warning: Error disposing camera: $e');
      }
    }
    
    // Also dispose custom controller if exists
    if (_cameraService.isUsingCustomController) {
      try {
        await _cameraService.customController?.dispose();
      } catch (e) {
          AppLogger.debug('   ⚠️ Warning: Error disposing custom controller: $e');
      }
    }
    
    // Clear current camera selection
    _currentCamera = null;
    
    // Clear any previous errors
    _errorMessage = null;
    
    // Reload cameras
    await loadCameras();
    
    // Select and initialize the first camera
    if (_availableCameras.isNotEmpty) {
      _currentCamera = _availableCameras.first;
      AppLogger.debug('📷 Selected first camera: ${_currentCamera!.name}');
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
    // Don't switch if it's the same camera
    if (_currentCamera?.name == camera.name) {
      AppLogger.debug('⚠️ Already using camera: ${camera.name}');
      return;
    }

    AppLogger.debug('🔄 Switching camera:');
    AppLogger.debug('   From: ${_currentCamera?.name ?? "none"} (${_currentCamera?.lensDirection ?? "unknown"})');
    AppLogger.debug('   To: ${camera.name} (${camera.lensDirection})');
    AppLogger.debug('   Camera sensor orientation: ${camera.sensorOrientation}');
    
    // Extract camera ID for logging (Android)
    if (!_isIOS) {
      final nameMatch = RegExp(r'Camera\s*(\d+)').firstMatch(camera.name);
      final cameraId = nameMatch != null ? nameMatch.group(1)! : camera.name;
      AppLogger.debug('   📋 Extracted camera ID: $cameraId');
    }
    
    // CRITICAL: Reload cameras to get fresh CameraDescription objects from the system
    // This ensures we're using the exact objects that iOS recognizes
    AppLogger.debug('   Reloading camera list to get fresh CameraDescription objects...');
    await loadCameras();
    
    // Find the exact match in the freshly loaded list
    final matchingCamera = _availableCameras.firstWhere(
      (c) => c.name == camera.name,
      orElse: () {
        AppLogger.debug('⚠️ WARNING: Camera not found in available list, using provided camera');
        return camera;
      },
    );
    
    if (matchingCamera.name != camera.name) {
      AppLogger.debug('❌ ERROR: Camera mismatch in switch!');
    } else {
      AppLogger.debug('✅ Found matching camera in available list');
      AppLogger.debug('   Using fresh CameraDescription: ${matchingCamera.name}');
      AppLogger.debug('   Camera direction: ${matchingCamera.lensDirection}');
    }
    
    _currentCamera = matchingCamera;
    await initializeCamera(matchingCamera);
  }

  /// Initializes the camera with the selected camera
  Future<void> initializeCamera(CameraDescription camera) async {
    _isInitializing = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // CRITICAL: Dispose the old controller completely before starting a new one
      // This forces iPadOS to release the hardware lock on the previous camera
      if (_cameraController != null) {
        AppLogger.debug('🔄 Disposing existing camera controller before switch...');
        try {
          await _cameraController!.dispose();
          AppLogger.debug('   ✅ Existing controller disposed successfully');
        } catch (e) {
          AppLogger.debug('   ⚠️ Warning: Error disposing existing controller: $e');
        }
        _cameraController = null;
        // Small delay to ensure disposal is complete
        await Future.delayed(const Duration(milliseconds: 200));
      }

      // Debug: Log which camera is being initialized
      AppLogger.debug('📸 CaptureViewModel.initializeCamera called:');
      AppLogger.debug('   Camera name: ${camera.name}');
      AppLogger.debug('   Camera direction: ${camera.lensDirection}');
      AppLogger.debug('   Camera sensor orientation: ${camera.sensorOrientation}');
      
      // Set Crashlytics context for better error tracking
      await CrashlyticsHelper.setCameraContext(
        cameraId: camera.name,
        cameraDirection: camera.lensDirection.toString(),
        isExternal: camera.lensDirection == CameraLensDirection.external,
      );
      CrashlyticsHelper.log('Initializing camera: ${camera.name}');
      
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
          } catch (e) {
            AppLogger.debug('❌ ERROR: Failed to start preview: $e');
            _errorMessage = 'Failed to start camera preview: $e';
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
    } on app_exceptions.PermissionException catch (e) {
      _errorMessage = e.message;
      notifyListeners();
    } on app_exceptions.CameraException catch (e) {
      _errorMessage = e.message;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to initialize camera: $e';
      notifyListeners();
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  /// Captures a photo
  Future<void> capturePhoto() async {
    if (!isReady) {
      _errorMessage = 'Camera not ready';
      notifyListeners();
      return;
    }

    _isCapturing = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final imageFile = await _cameraService.takePicture();
      // Get camera ID from either standard controller or current camera
      final cameraId = _cameraController?.description.name ?? _currentCamera?.name;
      final photoId = _uuid.v4();
      _capturedPhoto = PhotoModel(
        id: photoId,
        imageFile: imageFile,
        capturedAt: DateTime.now(),
        cameraId: cameraId,
      );
      
      // Track successful photo capture in Crashlytics
      await CrashlyticsHelper.setPhotoCaptureContext(
        photoId: photoId,
        sessionId: _sessionManager.sessionId,
      );
      CrashlyticsHelper.log('Photo captured successfully: $photoId');
      
      notifyListeners();
    } on app_exceptions.CameraException catch (e) {
      _errorMessage = e.message;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to capture photo: $e';
      notifyListeners();
    } finally {
      _isCapturing = false;
      notifyListeners();
    }
  }

  /// Clears the captured photo
  void clearCapturedPhoto() {
    _capturedPhoto = null;
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
    notifyListeners();

    try {
      // Get the image file from the captured photo
      final imageFile = _capturedPhoto!.imageFile;
      
      // Resize and encode image to meet API requirements:
      // - Size: 512x512 to 1024x1024 pixels
      // - Max size: ~2MB after base64 encoding
      // - Format: JPEG
      final base64Image = await ImageHelper.resizeAndEncodeImage(imageFile);
      
      // Step 3: Update session with photo (PATCH /api/sessions/{sessionId})
      // Note: selectedThemeId is not included here - it will be set later in theme selection
      final response = await _apiService.updateSession(
        sessionId: sessionId,
        userImageUrl: base64Image,
        selectedThemeId: null, // Theme will be selected later
      );
      
      // Save the response to SessionManager
      _sessionManager.setSessionFromResponse(response);
      
      // Step 3b: Preprocess image in background (fire-and-forget)
      // This runs validation, compression, and person detection ahead of time
      // Don't wait for it to complete - it's an optimization
      _apiService.preprocessImage(sessionId: sessionId);
      
      _isUploading = false;
      notifyListeners();
      return true;
    } on app_exceptions.ApiException catch (e) {
      _errorMessage = e.message;
      _isUploading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'Failed to upload photo: ${e.toString()}';
      _isUploading = false;
      notifyListeners();
      return false;
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
      
      // Resize and encode image to meet API requirements
      final base64Image = await ImageHelper.resizeAndEncodeImage(imageFile);
      
      // Update session via API: PATCH /api/sessions/{sessionId}
      final response = await _apiService.updateSession(
        sessionId: sessionId,
        userImageUrl: base64Image,
        selectedThemeId: selectedThemeId,
      );
      
      // Save the response to SessionManager
      _sessionManager.setSessionFromResponse(response);
      
      _isUploading = false;
      notifyListeners();
      return true;
    } on app_exceptions.ApiException catch (e) {
      _errorMessage = e.message;
      _isUploading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'Failed to update session: ${e.toString()}';
      _isUploading = false;
      notifyListeners();
      return false;
    }
  }

  /// Disposes the camera controller
  @override
  void dispose() {
    _cameraService.dispose();
    _cameraController = null;
    super.dispose();
  }
}

