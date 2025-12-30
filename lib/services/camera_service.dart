import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' if (dart.library.html) 'dart:html' as io;
import 'package:cross_file/cross_file.dart';
import '../utils/exceptions.dart' as app_exceptions;
import '../utils/constants.dart';
import 'custom_camera_controller.dart';

class CameraService {
  List<CameraDescription>? _cameras;
  CameraController? _controller;
  CustomCameraController? _customController;
  bool _useCustomController = false;

  List<CameraDescription>? get cameras => _cameras;

  /// Initializes available cameras
  /// Returns all cameras exactly as received from availableCameras()
  Future<List<CameraDescription>> getAvailableCameras() async {
    try {
      _cameras = await availableCameras();

      // Debug: Log all detected cameras
      print('📷 Detected ${_cameras!.length} camera(s):');
      for (final camera in _cameras!) {
        print('  - Name: "${camera.name}", Direction: ${camera.lensDirection}');
      }
      print('');

      // Return cameras directly - no conversion, no deduplication, no sorting
      print('📋 Final camera list (${_cameras!.length} cameras):');
      for (int i = 0; i < _cameras!.length; i++) {
        print('   ${i + 1}. ${_cameras![i].name}');
      }
      print('');

      return _cameras!;
    } catch (e) {
      throw app_exceptions.CameraException(
          '${AppConstants.kErrorCameraInitialization}: $e');
    }
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

    throw app_exceptions.PermissionException(
        AppConstants.kErrorCameraPermission);
  }

  /// Initializes camera controller
  Future<void> initializeCamera(CameraDescription camera) async {
    try {
      // Debug: Log which camera is being initialized
      print('🔧 CameraService.initializeCamera called:');
      print('   Camera name: ${camera.name}');
      print('   Camera direction: ${camera.lensDirection}');

      await checkAndRequestPermission();

      // CRITICAL: Aggressively dispose previous controller for external cameras
      // iOS needs the AVCaptureSession to be completely released before switching
      if (_controller != null) {
        final previousCameraName = _controller!.description.name;
        final previousDeviceId = previousCameraName.contains(':')
            ? previousCameraName.split(':').last.split(',').first
            : 'unknown';
        print(
            '   Disposing previous controller: $previousCameraName (device ID: $previousDeviceId)');

        try {
          // Stop any active preview first
          if (_controller!.value.isInitialized) {
            print('   Stopping camera preview...');
            // CameraController doesn't have a stop method, but dispose should handle it
          }

          await _controller!.dispose();
          print('   ✅ Previous controller disposed successfully');
        } catch (e) {
          print('   ⚠️ Warning: Error disposing previous controller: $e');
        }

        _controller = null;

        // CRITICAL: Longer delay for external cameras to ensure AVCaptureSession is fully released
        // iOS needs time to release the hardware lock, especially when switching from built-in to external
        print('   Waiting for camera hardware to be fully released...');
        await Future.delayed(const Duration(milliseconds: 1000));
        print('   ✅ Wait complete');
      }

      // CRITICAL: Reload camera list to get fresh CameraDescription objects
      // iOS may cache camera objects, so we need the latest from the system
      // This is especially important for external cameras that may be connected/disconnected
      print(
          '   Reloading camera list to get fresh CameraDescription objects...');
      _cameras = await availableCameras();
      print('   ✅ Reloaded ${_cameras!.length} cameras from system');

      // Additional delay after reload to ensure system has updated
      await Future.delayed(const Duration(milliseconds: 200));

      // Find the exact CameraDescription by device ID (name)
      // This ensures we're using the exact object that iOS recognizes
      CameraDescription cameraToUse;
      try {
        final exactMatch = _cameras!.firstWhere(
          (c) => c.name == camera.name,
        );
        cameraToUse = exactMatch;
        print('   ✅ Found exact CameraDescription match in fresh system list');
        print(
            '   Match details: name=${exactMatch.name}, direction=${exactMatch.lensDirection}');
      } catch (e) {
        print('   ⚠️ Camera not found in fresh list, using provided camera');
        print('   This may cause iOS to select the wrong camera!');
        cameraToUse = camera;
      }

      // CRITICAL WORKAROUND: If multiple cameras have the same lensDirection,
      // iOS may select the wrong one. We need to ensure we're requesting the correct device ID.
      // Extract device ID to verify we're targeting the right camera
      String? targetDeviceId;

      if (cameraToUse.name.contains(':')) {
        targetDeviceId = cameraToUse.name.split(':').last.split(',').first;
        print('   🎯 Target device ID: $targetDeviceId');

        // Log all cameras with the same direction to see the conflict
        final sameDirectionCameras = _cameras!
            .where(
              (c) => c.lensDirection == cameraToUse.lensDirection,
            )
            .toList();

        if (sameDirectionCameras.length > 1) {
          print(
              '   ⚠️ WARNING: Multiple cameras with same direction detected:');
          for (var cam in sameDirectionCameras) {
            final deviceId = cam.name.contains(':')
                ? cam.name.split(':').last.split(',').first
                : 'unknown';
            final isTarget = cam.name == cameraToUse.name;
            print(
                '     ${isTarget ? ">>> " : "    "}Device ID: $deviceId, Name: ${cam.name}${isTarget ? " <-- TARGET" : ""}');
          }
          print(
              '   ⚠️ iOS may select the wrong camera due to same lensDirection!');
          print(
              '   🔧 Using custom camera controller to select by device ID...');

          // Use custom camera controller for device ID selection
          if (!kIsWeb && io.Platform.isIOS) {
            try {
              // Dispose standard controller if exists
              if (_controller != null) {
                await _controller!.dispose();
                _controller = null;
              }

              // Use custom controller
              _customController = CustomCameraController();
              await _customController!.initialize(targetDeviceId);
              await _customController!.startPreview();
              _useCustomController = true;

              print(
                  '   ✅ Custom camera controller initialized with device ID $targetDeviceId');
              print('   ✅ This bypasses the lensDirection limitation!');
              return; // Exit early - custom controller handles everything
            } catch (e) {
              print(
                  '   ⚠️ Custom controller failed, falling back to standard controller: $e');
              _useCustomController = false;
              // Continue with standard controller initialization
            }
          }
        }
      }

      // Log all available cameras for debugging
      print('   Available cameras in system:');
      for (var cam in _cameras!) {
        final isTarget = cam.name == camera.name;
        final deviceId = cam.name.contains(':')
            ? cam.name.split(':').last.split(',').first
            : 'unknown';
        print(
            '     ${isTarget ? ">>> " : "    "}Device ID: $deviceId, Name: ${cam.name}, Direction: ${cam.lensDirection}${isTarget ? " <-- TARGET" : ""}');
      }

      // Create new controller with the specified camera
      print('   Creating new controller for: ${cameraToUse.name}');
      print('   Camera direction: ${cameraToUse.lensDirection}');
      print('   Camera sensor orientation: ${cameraToUse.sensorOrientation}');

      print('   Creating CameraController with:');
      print('     - Camera name: ${cameraToUse.name}');
      print('     - Direction: ${cameraToUse.lensDirection}');
      print('     - Sensor orientation: ${cameraToUse.sensorOrientation}');

      _controller = CameraController(
        cameraToUse, // Use the exact match from system list
        ResolutionPreset.high,
        enableAudio: false,
      );

      print('   Initializing CameraController...');
      print('   This may take longer for external cameras...');

      // Initialize with timeout to catch any issues
      await _controller!.initialize().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Camera initialization timed out after 10 seconds');
        },
      );

      print('   ✅ CameraController initialized');

      // Additional small delay after initialization to ensure camera is ready
      await Future.delayed(const Duration(milliseconds: 300));

      // Verify the controller is using the correct camera
      if (_controller != null) {
        final activeCamera = _controller!.description;
        print('✅ Controller initialized successfully:');
        print('   Active camera name: ${activeCamera.name}');
        print('   Active camera direction: ${activeCamera.lensDirection}');
        print(
            '   Active camera sensor orientation: ${activeCamera.sensorOrientation}');

        // CRITICAL: For external cameras, we MUST verify by device ID (name), not just direction
        // iOS may report multiple cameras with the same lensDirection, so name matching is essential
        final nameMatches = activeCamera.name == cameraToUse.name;
        final directionMatches =
            activeCamera.lensDirection == cameraToUse.lensDirection;

        // Extract device IDs for comparison
        String? requestedDeviceId;
        String? activeDeviceId;
        if (cameraToUse.name.contains(':')) {
          requestedDeviceId = cameraToUse.name.split(':').last.split(',').first;
        }
        if (activeCamera.name.contains(':')) {
          activeDeviceId = activeCamera.name.split(':').last.split(',').first;
        }

        print('   Device ID comparison:');
        print('     Requested device ID: $requestedDeviceId');
        print('     Active device ID: $activeDeviceId');

        // The name (device ID) MUST match exactly - this is the only reliable identifier
        if (!nameMatches) {
          print('');
          print('❌❌❌ CRITICAL ERROR: iOS selected the wrong camera! ❌❌❌');
          print('');
          print('   Requested:');
          print('     Device ID: $requestedDeviceId');
          print('     Name: ${cameraToUse.name}');
          print('     Direction: ${cameraToUse.lensDirection}');
          print('');
          print('   Actually Selected:');
          print('     Device ID: $activeDeviceId');
          print('     Name: ${activeCamera.name}');
          print('     Direction: ${activeCamera.lensDirection}');
          print('');
          print('   ⚠️ ROOT CAUSE:');
          print(
              '   The Flutter camera package uses lensDirection to match cameras.');
          print(
              '   When multiple cameras have the same lensDirection (front),');
          print(
              '   iOS selects the first one it finds, not the one we requested.');
          print('');
          print(
              '   This is a FUNDAMENTAL LIMITATION of the Flutter camera package.');
          print(
              '   It cannot force iOS to use a specific device ID when cameras');
          print('   share the same lensDirection.');
          print('');
          print('   💡 POSSIBLE SOLUTIONS:');
          print(
              '   1. Create a custom camera controller using platform channel');
          print(
              '   2. Fork the Flutter camera package to support device ID selection');
          print(
              '   3. Wait for Flutter camera package to add device ID support');
          print(
              '   4. Use a different camera library that supports device ID selection');
          print('');

          // Dispose the wrong camera
          await _controller!.dispose();
          _controller = null;

          throw app_exceptions.CameraException(
              'Camera selection failed: iOS selected wrong camera. '
              'Requested device ID: $requestedDeviceId (${cameraToUse.name}), '
              'Got device ID: $activeDeviceId (${activeCamera.name}). '
              'This is a known Flutter camera package limitation when external cameras '
              'report the same lensDirection as built-in cameras.');
        } else {
          print(
              '✅ Camera device ID verification passed - correct camera is active');
          if (!directionMatches) {
            print(
                '   ⚠️ Note: Direction mismatch (${cameraToUse.lensDirection} vs ${activeCamera.lensDirection}), but device ID matches');
          }
        }
      }
    } catch (e) {
      print('❌ Error initializing camera: $e');
      throw app_exceptions.CameraException(
          '${AppConstants.kErrorCameraInitialization}: $e');
    }
  }

  /// Gets the current camera controller
  CameraController? get controller => _useCustomController ? null : _controller;

  /// Gets the custom camera controller (when using device ID selection)
  CustomCameraController? get customController =>
      _useCustomController ? _customController : null;

  /// Checks if using custom controller
  bool get isUsingCustomController => _useCustomController;

  /// Takes a picture and returns the XFile (works on all platforms including web)
  Future<XFile> takePicture() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      throw app_exceptions.CameraException('Camera not initialized');
    }

    try {
      final XFile image = await _controller!.takePicture();
      return image;
    } catch (e) {
      throw app_exceptions.CameraException(
          '${AppConstants.kErrorPhotoCapture}: $e');
    }
  }

  /// Disposes the camera controller
  void dispose() {
    _controller?.dispose();
    _controller = null;
    _customController?.dispose();
    _customController = null;
    _useCustomController = false;
  }
}
