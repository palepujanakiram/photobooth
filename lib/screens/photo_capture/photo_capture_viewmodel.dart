import 'dart:convert';
import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:camera/camera.dart';
import 'package:uuid/uuid.dart';
import 'photo_model.dart';
import '../../services/camera_service.dart';
import '../../services/api_service.dart';
import '../../services/session_manager.dart';
import '../../utils/exceptions.dart' as app_exceptions;

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
      
      print('📋 CaptureViewModel.loadCameras - Found ${_availableCameras.length} cameras:');
      for (var camera in _availableCameras) {
        print('   - ${camera.name} (Direction: ${camera.lensDirection})');
      }
      
      // If no camera is currently selected and cameras are available, select the first one
      if (_currentCamera == null && _availableCameras.isNotEmpty) {
        _currentCamera = _availableCameras.first;
        print('📷 Auto-selected first camera: ${_currentCamera!.name}');
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
    print('🔄 Resetting camera screen and initializing cameras...');
    
    // Clear any captured photo
    _capturedPhoto = null;
    
    // Dispose current camera controller
    if (_cameraController != null) {
      print('   Disposing current camera controller...');
      try {
        await _cameraController!.dispose();
        _cameraController = null;
      } catch (e) {
        print('   ⚠️ Warning: Error disposing camera: $e');
      }
    }
    
    // Also dispose custom controller if exists
    if (_cameraService.isUsingCustomController) {
      try {
        await _cameraService.customController?.dispose();
      } catch (e) {
        print('   ⚠️ Warning: Error disposing custom controller: $e');
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
      print('📷 Selected first camera: ${_currentCamera!.name}');
      await initializeCamera(_currentCamera!);
    } else {
      print('⚠️ No cameras available');
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
      print('⚠️ Already using camera: ${camera.name}');
      return;
    }

    print('🔄 Switching camera:');
    print('   From: ${_currentCamera?.name ?? "none"}');
    print('   To: ${camera.name}');
    print('   Camera direction: ${camera.lensDirection}');
    print('   Camera sensor orientation: ${camera.sensorOrientation}');
    
    // CRITICAL: Reload cameras to get fresh CameraDescription objects from the system
    // This ensures we're using the exact objects that iOS recognizes
    print('   Reloading camera list to get fresh CameraDescription objects...');
    await loadCameras();
    
    // Find the exact match in the freshly loaded list
    final matchingCamera = _availableCameras.firstWhere(
      (c) => c.name == camera.name,
      orElse: () {
        print('⚠️ WARNING: Camera not found in available list, using provided camera');
        return camera;
      },
    );
    
    if (matchingCamera.name != camera.name) {
      print('❌ ERROR: Camera mismatch in switch!');
    } else {
      print('✅ Found matching camera in available list');
      print('   Using fresh CameraDescription: ${matchingCamera.name}');
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
        print('🔄 Disposing existing camera controller before switch...');
        try {
          await _cameraController!.dispose();
          print('   ✅ Existing controller disposed successfully');
        } catch (e) {
          print('   ⚠️ Warning: Error disposing existing controller: $e');
        }
        _cameraController = null;
        // Small delay to ensure disposal is complete
        await Future.delayed(const Duration(milliseconds: 200));
      }

      // Debug: Log which camera is being initialized
      print('📸 CaptureViewModel.initializeCamera called:');
      print('   Camera name: ${camera.name}');
      print('   Camera direction: ${camera.lensDirection}');
      print('   Camera sensor orientation: ${camera.sensorOrientation}');
      
      // Use the camera directly
      final cameraToUse = camera;
      
      await _cameraService.initializeCamera(cameraToUse);
      _cameraController = _cameraService.controller;
      
      // Debug: Verify which camera was actually initialized
      if (_cameraController != null) {
        final activeCamera = _cameraController!.description;
        print('✅ CaptureViewModel - Camera controller obtained:');
        print('   Active camera name: ${activeCamera.name}');
        print('   Active camera direction: ${activeCamera.lensDirection}');
        print('   Active camera sensor orientation: ${activeCamera.sensorOrientation}');
        
        // Verify it's the correct camera - check both name AND lensDirection
        // External cameras on iPadOS should report CameraLensDirection.external
        final nameMatches = activeCamera.name == cameraToUse.name;
        final directionMatches = activeCamera.lensDirection == cameraToUse.lensDirection;
        
        if (!nameMatches || !directionMatches) {
          print('❌ ERROR: Wrong camera is active!');
          print('   Expected name: ${cameraToUse.name}');
          print('   Got name: ${activeCamera.name}');
          print('   Expected direction: ${cameraToUse.lensDirection}');
          print('   Got direction: ${activeCamera.lensDirection}');
          _errorMessage = 'Wrong camera initialized. Expected ${cameraToUse.name} (${cameraToUse.lensDirection}), but got ${activeCamera.name} (${activeCamera.lensDirection}).';
          notifyListeners();
          return;
        }
        
        print('✅ Camera verification passed in CaptureViewModel');
        print('   ✅ Active direction: ${activeCamera.lensDirection}');
        _currentCamera = camera;
      } else {
        print('❌ ERROR: Camera controller is null after initialization!');
        _errorMessage = 'Camera controller is null after initialization';
        notifyListeners();
        return;
      }
      
      notifyListeners();
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
      _capturedPhoto = PhotoModel(
        id: _uuid.v4(),
        imageFile: imageFile,
        capturedAt: DateTime.now(),
        cameraId: _cameraController?.description.name,
      );
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

  /// Converts image file to base64 data URL
  /// Works with XFile on all platforms (mobile and web)
  Future<String> _convertImageToBase64(XFile imageFile) async {
    try {
      // Read image bytes from XFile (works on all platforms)
      final bytes = await imageFile.readAsBytes();
      
      // Check if file is not empty
      if (bytes.isEmpty) {
        throw Exception('Image file is empty: ${imageFile.path}');
      }
      
      // Encode to base64
      final base64String = base64Encode(bytes);
      
      // Determine image format from file extension or mime type
      final extension = imageFile.path.toLowerCase().split('.').last;
      final mimeType = imageFile.mimeType ?? 
          (extension == 'png' ? 'image/png' : 'image/jpeg');
      
      // Return data URL format: data:image/jpeg;base64,...
      return 'data:$mimeType;base64,$base64String';
    } catch (e) {
      throw Exception('Failed to convert image to base64: $e');
    }
  }

  /// Updates session with captured photo and selected theme
  /// Gets the image from the camera file and uploads it via API
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
      
      // Convert image from XFile to base64 data URL
      // Format: data:image/jpeg;base64,/9j/4AAQSkZJRg...
      // XFile.readAsBytes() works on all platforms (mobile and web)
      final base64Image = await _convertImageToBase64(imageFile);
      
      // Update session via API: PATCH /api/sessions/{sessionId}
      final response = await _apiService.updateSession(
        sessionId: sessionId,
        userImageUrl: base64Image,
        selectedThemeId: selectedThemeId,
      );
      
      // Save the response to SessionManager
      // Response includes: id, userImageUrl, selectedThemeId, selectedCategoryId, attemptsUsed, generatedImages
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

