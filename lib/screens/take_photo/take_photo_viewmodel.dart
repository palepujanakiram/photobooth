import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:camera/camera.dart';
import 'package:uuid/uuid.dart';
import '../../services/camera_service.dart';
import '../../services/uvc_camera_wrapper.dart';
import '../../utils/logger.dart';
import '../photo_capture/photo_model.dart';

class TakePhotoViewModel extends ChangeNotifier {
  final CameraService _cameraService;
  final Uuid _uuid = const Uuid();
  
  List<CameraDescription> _availableCameras = [];
  CameraDescription? _selectedCamera;
  bool _isLoadingCameras = false;
  bool _isInitializing = false;
  bool _isCapturing = false;
  String? _errorMessage;
  PhotoModel? _capturedPhoto;

  TakePhotoViewModel({
    CameraService? cameraService,
  }) : _cameraService = cameraService ?? CameraService();

  List<CameraDescription> get availableCameras => _availableCameras;
  CameraDescription? get selectedCamera => _selectedCamera;
  bool get isLoadingCameras => _isLoadingCameras;
  bool get isInitializing => _isInitializing;
  bool get isCapturing => _isCapturing;
  String? get errorMessage => _errorMessage;
  bool get hasError => _errorMessage != null;
  PhotoModel? get capturedPhoto => _capturedPhoto;
  
  // Camera controller getters
  CameraController? get cameraController => _cameraService.controller;
  bool get isReady {
    // Check if using UVC camera
    if (_cameraService.isUsingUvcCamera) {
      // For UVC, check if initialized (preview starts when view is created)
      return _cameraService.uvcCameraWrapper?.isInitialized ?? false;
    }
    // Check if using custom controller
    if (_cameraService.isUsingCustomController) {
      return _cameraService.customController?.isPreviewRunning ?? false;
    }
    // Check standard controller
    return _cameraService.controller != null &&
        _cameraService.controller!.value.isInitialized;
  }
  bool get isUsingCustomController => _cameraService.isUsingCustomController;
  bool get isUsingUvcCamera => _cameraService.isUsingUvcCamera;
  int? get textureId => _cameraService.textureId;
  CameraService get cameraService => _cameraService;
  UvcCameraWrapper? get uvcWrapper => _cameraService.uvcCameraWrapper;

  /// Loads available cameras and selects external camera by default
  Future<void> loadCameras() async {
    _isLoadingCameras = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _availableCameras = await _cameraService.getAvailableCameras();
      
      AppLogger.debug('📋 TakePhotoViewModel - Found ${_availableCameras.length} cameras:');
      for (var camera in _availableCameras) {
        AppLogger.debug('   - ${camera.name} (Direction: ${camera.lensDirection})');
      }

      // Select external camera by default, or first camera if no external camera
      CameraDescription? defaultCamera;
      for (var camera in _availableCameras) {
        if (camera.lensDirection == CameraLensDirection.external) {
          defaultCamera = camera;
          break;
        }
      }
      
      if (defaultCamera == null && _availableCameras.isNotEmpty) {
        defaultCamera = _availableCameras.first;
      }

      if (defaultCamera != null) {
        await selectCamera(defaultCamera);
      }
    } catch (e) {
      _errorMessage = 'Failed to load cameras: $e';
      AppLogger.debug('❌ Error loading cameras: $e');
    } finally {
      _isLoadingCameras = false;
      notifyListeners();
    }
  }

  /// Selects a camera and initializes it
  Future<void> selectCamera(CameraDescription camera) async {
    if (_selectedCamera?.name == camera.name && isReady) {
      AppLogger.debug('📷 Camera already selected and ready: ${camera.name}');
      return;
    }

    // Prevent multiple simultaneous initializations
    if (_isInitializing) {
      AppLogger.debug('⚠️ Camera initialization already in progress, skipping...');
      return;
    }

    _isInitializing = true;
    _errorMessage = null;
    _selectedCamera = camera;
    notifyListeners();

    try {
      AppLogger.debug('📷 Selecting camera: ${camera.name}');
      
      // Initialize with timeout to prevent hanging
      await _cameraService.initializeCamera(camera).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw Exception('Camera initialization timed out after 15 seconds');
        },
      );
      
      AppLogger.debug('✅ Camera initialized: ${camera.name}');
      
      // Small delay to ensure camera is ready
      await Future.delayed(const Duration(milliseconds: 300));
    } catch (e) {
      _errorMessage = 'Failed to initialize camera: $e';
      AppLogger.debug('❌ Error initializing camera: $e');
      // Clear selected camera on error
      _selectedCamera = null;
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  /// Captures a photo from the selected camera
  Future<PhotoModel?> capturePhoto() async {
    if (!isReady) {
      _errorMessage = 'Camera not ready';
      notifyListeners();
      return null;
    }

    if (_selectedCamera == null) {
      _errorMessage = 'No camera selected';
      notifyListeners();
      return null;
    }

    _isCapturing = true;
    _errorMessage = null;
    notifyListeners();

    try {
      AppLogger.debug('📸 Capturing photo from camera: ${_selectedCamera!.name}');
      final imageFile = await _cameraService.takePicture();
      
      final photo = PhotoModel(
        id: _uuid.v4(),
        imageFile: imageFile,
        capturedAt: DateTime.now(),
        cameraId: _selectedCamera!.name,
      );

      _capturedPhoto = photo;
      AppLogger.debug('✅ Photo captured successfully: ${photo.id}');
      
      notifyListeners();
      return photo;
    } catch (e) {
      _errorMessage = 'Failed to capture photo: $e';
      AppLogger.debug('❌ Error capturing photo: $e');
      notifyListeners();
      return null;
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

  @override
  void dispose() {
    _cameraService.dispose();
    super.dispose();
  }
}
