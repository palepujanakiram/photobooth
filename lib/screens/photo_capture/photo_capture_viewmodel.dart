import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'package:uuid/uuid.dart';
import 'photo_model.dart';
import '../camera_selection/camera_info_model.dart';
import '../../services/camera_service.dart';
import '../../utils/exceptions.dart' as app_exceptions;

class CaptureViewModel extends ChangeNotifier {
  final CameraService _cameraService;
  final Uuid _uuid = const Uuid();
  CameraController? _cameraController;
  PhotoModel? _capturedPhoto;
  bool _isInitializing = false;
  bool _isCapturing = false;
  String? _errorMessage;

  CaptureViewModel({CameraService? cameraService})
      : _cameraService = cameraService ?? CameraService();

  CameraController? get cameraController => _cameraController;
  PhotoModel? get capturedPhoto => _capturedPhoto;
  bool get isInitializing => _isInitializing;
  bool get isCapturing => _isCapturing;
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

  /// Disposes the camera controller
  @override
  void dispose() {
    _cameraService.dispose();
    _cameraController = null;
    super.dispose();
  }
}

