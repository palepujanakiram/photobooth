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
  /// Returns unique cameras (deduplicated by lens direction for front/back, by name for external)
  /// Includes device front/back cameras and externally connected cameras
  Future<List<CameraInfoModel>> getAvailableCameras() async {
    try {
      _cameras = await availableCameras();
      
      // Deduplicate cameras to avoid duplicates
      // For front/back cameras: use lens direction as unique identifier (one per direction)
      // For external cameras: use name as unique identifier (multiple external cameras allowed)
      final Map<String, CameraDescription> uniqueCameras = {};
      final Set<CameraLensDirection> seenDirections = {};
      
      for (final camera in _cameras!) {
        if (camera.lensDirection == CameraLensDirection.front ||
            camera.lensDirection == CameraLensDirection.back) {
          // For front/back cameras, use lens direction as key (only one per direction)
          // This prevents duplicates of the same physical camera
          if (!seenDirections.contains(camera.lensDirection)) {
            seenDirections.add(camera.lensDirection);
            final uniqueKey = camera.lensDirection.toString();
            uniqueCameras[uniqueKey] = camera;
          }
        } else {
          // For external cameras, use combination of direction and name
          // This allows multiple external cameras but prevents duplicates
          final uniqueKey = '${camera.lensDirection.toString()}_${camera.name}';
          if (!uniqueCameras.containsKey(uniqueKey)) {
            uniqueCameras[uniqueKey] = camera;
          }
        }
      }
      
      // Convert to list and create CameraInfoModel for each unique camera
      final cameraList = uniqueCameras.values.map((camera) {
        return CameraInfoModel(
          camera: camera,
          name: _getCameraName(camera),
          isFrontFacing: camera.lensDirection == CameraLensDirection.front,
        );
      }).toList();
      
      // Sort cameras: front camera first, then back camera, then external cameras
      cameraList.sort((a, b) {
        // Front camera first
        if (a.isFrontFacing && !b.isFrontFacing) {
          return -1;
        }
        if (!a.isFrontFacing && b.isFrontFacing) {
          return 1;
        }
        // Then back camera
        if (!a.isFrontFacing && !b.isFrontFacing) {
          if (a.camera.lensDirection == CameraLensDirection.back &&
              b.camera.lensDirection != CameraLensDirection.back) {
            return -1;
          }
          if (a.camera.lensDirection != CameraLensDirection.back &&
              b.camera.lensDirection == CameraLensDirection.back) {
            return 1;
          }
        }
        // Then by name for external cameras
        return a.name.compareTo(b.name);
      });
      
      return cameraList;
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
    } else if (camera.lensDirection == CameraLensDirection.external) {
      // External camera - use the camera name or a descriptive name
      return camera.name.isNotEmpty && camera.name != '0' && camera.name != '1'
          ? camera.name
          : 'External Camera';
    }
    // Fallback for unknown camera types
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

