import 'dart:io';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import '../screens/camera_selection/camera_info_model.dart';
import '../utils/exceptions.dart' as app_exceptions;
import '../utils/constants.dart';

class CameraService {
  List<CameraDescription>? _cameras;
  CameraController? _controller;

  List<CameraDescription>? get cameras => _cameras;

  /// Initializes available cameras
  Future<List<CameraInfoModel>> getAvailableCameras() async {
    try {
      _cameras = await availableCameras();
      return _cameras!
          .map((camera) => CameraInfoModel(
                camera: camera,
                name: _getCameraName(camera),
                isFrontFacing: camera.lensDirection == CameraLensDirection.front,
              ))
          .toList();
    } catch (e) {
      throw app_exceptions.CameraException(
          '${AppConstants.kErrorCameraInitialization}: $e');
    }
  }

  String _getCameraName(CameraDescription camera) {
    if (camera.lensDirection == CameraLensDirection.front) {
      return 'Front Camera';
    } else if (camera.lensDirection == CameraLensDirection.back) {
      return 'Back Camera';
    }
    return 'Camera ${camera.name}';
  }

  /// Checks and requests camera permission
  Future<bool> checkAndRequestPermission() async {
    final status = await Permission.camera.status;
    if (status.isGranted) {
      return true;
    }

    if (status.isDenied) {
      final result = await Permission.camera.request();
      return result.isGranted;
    }

    throw app_exceptions.PermissionException(AppConstants.kErrorCameraPermission);
  }

  /// Initializes camera controller
  Future<void> initializeCamera(CameraDescription camera) async {
    try {
      await checkAndRequestPermission();

      _controller?.dispose();
      _controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _controller!.initialize();
    } catch (e) {
      throw app_exceptions.CameraException(
          '${AppConstants.kErrorCameraInitialization}: $e');
    }
  }

  /// Gets the current camera controller
  CameraController? get controller => _controller;

  /// Takes a picture and returns the file
  Future<File> takePicture() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      throw app_exceptions.CameraException('Camera not initialized');
    }

    try {
      final XFile image = await _controller!.takePicture();
      return File(image.path);
    } catch (e) {
      throw app_exceptions.CameraException('${AppConstants.kErrorPhotoCapture}: $e');
    }
  }

  /// Disposes the camera controller
  void dispose() {
    _controller?.dispose();
    _controller = null;
  }
}

