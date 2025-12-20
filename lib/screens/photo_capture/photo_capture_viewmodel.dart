import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'package:uuid/uuid.dart';
import 'photo_model.dart';
import '../camera_selection/camera_info_model.dart';
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
  bool get isInitializing => _isInitializing;
  bool get isCapturing => _isCapturing;
  bool get isUploading => _isUploading;
  String? get errorMessage => _errorMessage;
  bool get hasError => _errorMessage != null;
  bool get isReady => _cameraController != null &&
      _cameraController!.value.isInitialized;

  /// Initializes the camera with the selected camera info
  Future<void> initializeCamera(CameraInfoModel cameraInfo) async {
    _isInitializing = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _cameraService.initializeCamera(cameraInfo.camera);
      _cameraController = _cameraService.controller;
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
  /// Reads the image directly from the camera file
  Future<String> _convertImageToBase64(File imageFile) async {
    try {
      // Verify file exists before reading
      if (!await imageFile.exists()) {
        throw Exception('Image file does not exist: ${imageFile.path}');
      }

      // Read image bytes from camera file
      final bytes = await imageFile.readAsBytes();
      
      // Check if file is not empty
      if (bytes.isEmpty) {
        throw Exception('Image file is empty: ${imageFile.path}');
      }
      
      // Encode to base64
      final base64String = base64Encode(bytes);
      
      // Determine image format from file extension
      final extension = imageFile.path.toLowerCase().split('.').last;
      final mimeType = extension == 'png' ? 'image/png' : 'image/jpeg';
      
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
      
      // Verify the file exists
      if (!await imageFile.exists()) {
        _errorMessage = 'Image file not found. Please capture the photo again.';
        _isUploading = false;
        notifyListeners();
        return false;
      }

      // Convert image from camera file to base64 data URL
      // Format: data:image/jpeg;base64,/9j/4AAQSkZJRg...
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

