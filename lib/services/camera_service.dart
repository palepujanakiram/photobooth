import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart';
import '../utils/exceptions.dart' as app_exceptions;
import '../utils/constants.dart';
import 'custom_camera_controller.dart';
import 'ios_camera_device_helper.dart';
import 'android_camera_device_helper.dart';

/// Helper function to check if running on iOS
/// Works on all platforms including web
bool get _isIOS {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.iOS;
}

class CameraService {
  List<CameraDescription>? _cameras;
  CameraController? _controller;
  CustomCameraController? _customController;
  bool _useCustomController = false;

  // Map camera names (unique IDs) to their localized names from iOS
  final Map<String, String> _cameraLocalizedNames = {};

  // Camera change callback
  Function(String event, Map<String, dynamic> cameraInfo)? onCameraChanged;

  // Method channel for iOS camera device operations
  static const _iosChannel = MethodChannel('com.photobooth/camera_device');

  bool _listenerSetup = false;

  List<CameraDescription>? get cameras => _cameras;

  /// Initialize the camera service and set up listeners
  Future<void> initialize() async {
    if (!_listenerSetup && _isIOS) {
      _setupCameraChangeListener();
      _listenerSetup = true;
    }
  }

  /// Set up listener for camera connection/disconnection events (iOS only)
  void _setupCameraChangeListener() {
    _iosChannel.setMethodCallHandler((call) async {
      if (call.method == 'onCameraChange') {
        final arguments = call.arguments as Map<dynamic, dynamic>;
        final event = arguments['event'] as String;
        final cameraInfo = Map<String, dynamic>.from(arguments);

        final uniqueID = cameraInfo['uniqueID'] as String? ?? 'unknown';
        final localizedName =
            cameraInfo['localizedName'] as String? ?? 'unknown';
        final isExternal = uniqueID.length > 30 || !uniqueID.contains(':');

        print('📱 Camera $event: $localizedName');
        print('   UniqueID: $uniqueID');
        print('   External: $isExternal');

        // Notify callback if set
        onCameraChanged?.call(event, cameraInfo);

        // Refresh camera list
        await refreshCameraList();
      }
    });

    print('✅ Camera change listener set up');
  }

  /// Request camera permission (iOS)
  Future<bool> requestCameraPermission() async {
    if (!_isIOS) {
      // Use permission_handler for other platforms
      final status = await Permission.camera.request();
      return status.isGranted;
    }

    try {
      final result = await _iosChannel.invokeMethod('requestCameraPermission');
      final status = result['status'] as String;

      print('📱 Camera permission status: $status');

      return status == 'authorized';
    } catch (e) {
      print('❌ Error requesting camera permission: $e');
      return false;
    }
  }

  /// Test external camera detection (iOS only)
  Future<Map<String, dynamic>?> testExternalCameras() async {
    if (!_isIOS) {
      print('⚠️ testExternalCameras is only available on iOS');
      return null;
    }

    try {
      final result = await _iosChannel.invokeMethod('testExternalCameras');
      final testInfo = Map<String, dynamic>.from(result);

      print('🔍 External Camera Test Results:');
      print('   Total devices: ${testInfo['totalDevices']}');
      print('   Built-in devices: ${testInfo['builtInDevices']}');
      print('   External devices: ${testInfo['externalDevices']}');

      final externalNames = testInfo['externalNames'] as List<dynamic>;
      if (externalNames.isNotEmpty) {
        print('   External camera names:');
        for (final name in externalNames) {
          print('     - $name');
        }
      }

      return testInfo;
    } catch (e) {
      print('❌ Error testing external cameras: $e');
      return null;
    }
  }

  /// Refresh the camera list (useful after connection/disconnection)
  Future<void> refreshCameraList() async {
    print('🔄 Refreshing camera list...');
    try {
      await getAvailableCameras();
      print('✅ Camera list refreshed');
    } catch (e) {
      print('❌ Error refreshing camera list: $e');
    }
  }

  /// Gets the localized name for a camera, or returns a fallback name
  String getCameraDisplayName(CameraDescription camera) {
    // Try to get from stored localized names
    final localizedName = _cameraLocalizedNames[camera.name];
    if (localizedName != null && localizedName.isNotEmpty) {
      return localizedName;
    }

    // Fallback: Generate a name based on camera properties
    if (camera.lensDirection == CameraLensDirection.back) {
      return 'Back Camera';
    } else if (camera.lensDirection == CameraLensDirection.front) {
      return 'Front Camera';
    } else if (camera.lensDirection == CameraLensDirection.external) {
      // Extract device ID for external cameras
      if (camera.name.contains(':')) {
        final deviceId = camera.name.split(':').last.split(',').first;
        return 'External Camera $deviceId';
      }
      return 'External Camera';
    }

    // Last resort: use device ID
    if (camera.name.contains(':')) {
      final deviceId = camera.name.split(':').last.split(',').first;
      return 'Camera $deviceId';
    }

    return 'Camera';
  }

  /// Initializes available cameras
  /// Filters cameras to only include those that are actually available/connected
  Future<List<CameraDescription>> getAvailableCameras() async {
    try {
      // Ensure listener is set up (iOS only)
      if (_isIOS && !_listenerSetup) {
        await initialize();
      }

      _cameras = await availableCameras();

      // Debug: Log all detected cameras
      print('📷 Detected ${_cameras!.length} camera(s) from Flutter:');
      for (final camera in _cameras!) {
        print('  - Name: "${camera.name}", Direction: ${camera.lensDirection}');
      }
      print('');

      // On Android, get cameras from native Camera2 API to detect USB cameras
      if (!_isIOS && !kIsWeb) {
        print('🤖 Android platform detected');
        print('📱 Flutter detected ${_cameras!.length} camera(s):');
        for (int i = 0; i < _cameras!.length; i++) {
          final camera = _cameras![i];
          final isExternal =
              camera.lensDirection == CameraLensDirection.external;
          print('   ${i + 1}. Name: "${camera.name}"');
          print('      Direction: ${camera.lensDirection}');
          print('      External: $isExternal');
          print('      Sensor Orientation: ${camera.sensorOrientation}');
          print('');
        }

        // Get cameras from Android Camera2 API (includes USB cameras)
        try {
          final androidCameras =
              await AndroidCameraDeviceHelper.getAllAvailableCameras();
          if (androidCameras != null && androidCameras.isNotEmpty) {
            print(
                '📱 Android Camera2 API reports ${androidCameras.length} camera(s):');
            print('');

            for (int i = 0; i < androidCameras.length; i++) {
              final androidCamera = androidCameras[i];
              final uniqueID =
                  androidCamera['uniqueID'] as String? ?? 'unknown';
              final localizedName =
                  androidCamera['localizedName'] as String? ?? 'unknown';

              // Check if this camera is external by matching with Flutter's camera list
              // External cameras on Android have CameraLensDirection.external
              final matchingFlutterCamera = _cameras!
                  .where(
                    (c) => c.name == uniqueID,
                  )
                  .firstOrNull;

              final isExternal = matchingFlutterCamera?.lensDirection ==
                  CameraLensDirection.external;

              print('  📷 Camera #${i + 1} Details:');
              print('     Unique ID: $uniqueID');
              print('     Name: "$localizedName"');
              print('     External: $isExternal');
              print('');

              // Store mapping for all cameras (not just external)
              if (localizedName != 'unknown' && localizedName.isNotEmpty) {
                // Try to match with Flutter camera by camera ID
                if (matchingFlutterCamera != null) {
                  _cameraLocalizedNames[uniqueID] = localizedName;
                  print(
                      '     💾 Stored mapping: $uniqueID -> "$localizedName"');
                } else {
                  // Camera not found in Flutter list - might be USB camera
                  print(
                      '     ⚠️ Camera $uniqueID not found in Flutter camera list');
                  print(
                      '     This might be a USB camera not detected by Flutter');

                  // Still store the mapping in case it's added later
                  if (isExternal) {
                    _cameraLocalizedNames[uniqueID] = localizedName;
                  }
                }
              }
            }
            print('');

            // Check if there are external cameras in Android that aren't in Flutter list
            final externalAndroidCameras = androidCameras.where((camera) {
              final uniqueID = camera['uniqueID'] as String? ?? 'unknown';
              final matchingFlutterCamera = _cameras!
                  .where(
                    (c) => c.name == uniqueID,
                  )
                  .firstOrNull;
              return matchingFlutterCamera?.lensDirection ==
                  CameraLensDirection.external;
            }).toList();

            if (externalAndroidCameras.isNotEmpty) {
              print(
                  '🔍 Found ${externalAndroidCameras.length} external camera(s) in Android:');
              for (final extCamera in externalAndroidCameras) {
                final uniqueID = extCamera['uniqueID'] as String? ?? 'unknown';
                final localizedName =
                    extCamera['localizedName'] as String? ?? 'unknown';
                final isInFlutterList =
                    _cameras!.any((c) => c.name == uniqueID);
                print(
                    '   ${isInFlutterList ? "✅" : "❌"} $localizedName (ID: $uniqueID)');
                if (!isInFlutterList) {
                  print(
                      '      ⚠️ This USB camera is not detected by Flutter camera package');
                }
              }
              print('');
            }
          } else {
            print('⚠️ Could not get Android camera list from Camera2 API');
          }
        } catch (e) {
          print('⚠️ Error getting Android cameras: $e');
        }
      }

      // On iOS, verify cameras actually exist using platform channel
      if (_isIOS) {
        try {
          final iosCameras =
              await IOSCameraDeviceHelper.getAllAvailableCameras();
          if (iosCameras != null && iosCameras.isNotEmpty) {
            print(
                '📱 iOS reports ${iosCameras.length} actually available camera(s):');
            print('');

            // Clear previous mappings
            _cameraLocalizedNames.clear();

            for (int i = 0; i < iosCameras.length; i++) {
              final iosCamera = iosCameras[i];
              final uniqueID = iosCamera['uniqueID'] as String? ?? 'unknown';
              final localizedName =
                  iosCamera['localizedName'] as String? ?? 'unknown';

              // Derive isExternal from uniqueID format
              // External cameras have UUID format (length > 30), built-in cameras have device ID format
              final isExternal =
                  uniqueID.length > 30 || !uniqueID.contains(':');

              // Extract deviceId from uniqueID for built-in cameras
              String deviceId = 'unknown';
              if (!isExternal && uniqueID.contains(':')) {
                deviceId = uniqueID.split(':').last;
              }

              print('  📷 Camera #${i + 1} Details:');
              print(
                  '     Name: "$localizedName" (length: ${localizedName.length})');
              if (localizedName == 'unknown') {
                print(
                    '     ⚠️  WARNING: localizedName not found in iOS response!');
                print('     Available keys: ${iosCamera.keys.join(", ")}');
              }
              print('     Unique ID: $uniqueID');
              print('     External: $isExternal');
              if (!isExternal) {
                print('     Device ID: $deviceId');
              }
              print('');

              // Store mapping from camera name to localized name
              // Flutter camera package uses a name format like:
              // "com.apple.avfoundation.avcapturedevice.built-in_video:8"
              // or for external: UUID format

              // For external cameras with UUID uniqueID
              if (isExternal) {
                _cameraLocalizedNames[uniqueID] = localizedName;
                print(
                    '     💾 Stored mapping (external): $uniqueID -> "$localizedName"');
              }

              // Try to match with Flutter cameras
              final matchingFlutterCameraIndex = _cameras!.indexWhere(
                (c) {
                  // For external cameras with UUID uniqueID, check if uniqueID matches
                  if (isExternal && c.name == uniqueID) {
                    return true;
                  }
                  // For built-in cameras, check if uniqueID matches or device ID matches
                  if (!isExternal) {
                    // Check if Flutter camera name matches uniqueID
                    if (c.name == uniqueID) {
                      return true;
                    }
                    // Or check if device ID matches
                    if (c.name.contains(':')) {
                      final flutterDeviceId =
                          c.name.split(':').last.split(',').first.trim();
                      if (flutterDeviceId == deviceId) {
                        return true;
                      }
                    }
                  }
                  return false;
                },
              );

              if (matchingFlutterCameraIndex >= 0) {
                final matchingFlutterCamera =
                    _cameras![matchingFlutterCameraIndex];

                // Check if Flutter's camera has the wrong direction
                // For external cameras, must be external
                // For built-in cameras, use Flutter's existing direction (it's usually correct)
                final correctDirection = isExternal
                    ? CameraLensDirection.external
                    : matchingFlutterCamera
                        .lensDirection; // Trust Flutter's direction for built-in

                if (matchingFlutterCamera.lensDirection != correctDirection) {
                  // Flutter has the wrong direction - replace with correct one
                  print(
                      '     ⚠️ Flutter camera has wrong direction: ${matchingFlutterCamera.lensDirection}');
                  print('     ✅ Correcting to: $correctDirection');

                  // Remove the incorrectly classified camera
                  _cameras!.removeAt(matchingFlutterCameraIndex);

                  // Add the correctly classified camera
                  final correctedCamera = CameraDescription(
                    name: isExternal ? uniqueID : matchingFlutterCamera.name,
                    lensDirection: correctDirection,
                    sensorOrientation: matchingFlutterCamera.sensorOrientation,
                  );

                  _cameras!.add(correctedCamera);
                  _cameraLocalizedNames[correctedCamera.name] = localizedName;
                  print(
                      '     ✅ Corrected camera: ${correctedCamera.name} -> "$localizedName" (${correctedCamera.lensDirection})');
                } else {
                  // Direction is correct, just store the mapping
                  _cameraLocalizedNames[matchingFlutterCamera.name] =
                      localizedName;
                  print(
                      '     💾 Stored mapping: ${matchingFlutterCamera.name} -> "$localizedName"');
                }
              } else {
                // Camera not found in Flutter's list
                if (isExternal) {
                  // For external cameras detected by iOS but not in Flutter's list,
                  // add them manually to the cameras list
                  print(
                      '     ➕ Adding external camera to list (not in Flutter availableCameras):');
                  print('        UniqueID: $uniqueID');
                  print('        Name: $localizedName');

                  final externalCamera = CameraDescription(
                    name:
                        uniqueID, // Use uniqueID as the name for external cameras
                    lensDirection: CameraLensDirection.external,
                    sensorOrientation: 0, // Default orientation
                  );

                  _cameras!.add(externalCamera);
                  _cameraLocalizedNames[uniqueID] = localizedName;
                  print(
                      '     ✅ Added external camera: $uniqueID -> "$localizedName"');
                } else {
                  print(
                      '     ⚠️ Camera with uniqueID $uniqueID not found in Flutter camera list');
                }
              }
            }
            print('');
          } else {
            print('⚠️ Could not get iOS camera list');
          }
        } catch (e) {
          print('⚠️ Error getting iOS cameras: $e');
        }
      }

      print('✅ Final camera list: ${_cameras!.length} camera(s)');
      for (int i = 0; i < _cameras!.length; i++) {
        final camera = _cameras![i];
        final displayName = getCameraDisplayName(camera);
        final isExternal = camera.lensDirection == CameraLensDirection.external;
        print(
            '   ${i + 1}. ${isExternal ? "🔌" : "📷"} $displayName (${camera.lensDirection})');
      }
      print('');

      return _cameras!;
    } catch (e) {
      print('❌ Error getting available cameras: $e');
      rethrow;
    }
  }

  /// Requests camera permission
  Future<bool> requestPermission() async {
    if (_isIOS) {
      // Use native iOS permission request
      return await requestCameraPermission();
    }

    // For other platforms, use permission_handler
    try {
      final status = await Permission.camera.request();
      if (status.isGranted) {
        print('✅ Camera permission granted');
        return true;
      } else if (status.isDenied) {
        print('❌ Camera permission denied');
        return false;
      } else if (status.isPermanentlyDenied) {
        print('❌ Camera permission permanently denied');
        // You might want to open app settings here
        await openAppSettings();
        return false;
      }
      return false;
    } catch (e) {
      print('❌ Error requesting camera permission: $e');
      return false;
    }
  }

  /// Initializes the camera with the selected camera
  Future<void> initializeCamera(CameraDescription camera) async {
    try {
      print('🎥 Initializing camera: ${camera.name}');
      print('   Direction: ${camera.lensDirection}');

      // Dispose any existing controller
      if (_controller != null) {
        await _controller!.dispose();
        _controller = null;
      }
      if (_customController != null) {
        await _customController!.dispose();
        _customController = null;
        _useCustomController = false;
      }

      // For external cameras on iOS, we may need to use a different approach
      // due to Flutter camera package limitations with device ID selection
      if (_isIOS && camera.lensDirection == CameraLensDirection.external) {
        print('   📱 External camera on iOS detected');
        print(
            '   🔍 Checking if custom controller is needed for device ID selection...');

        // Extract device ID
        String? deviceId;
        if (camera.name.contains(':')) {
          deviceId = camera.name.split(':').last.split(',').first;
          print('   Device ID from name: $deviceId');
        }

        // Try to use CustomCameraController for better device ID control
        if (deviceId != null && int.tryParse(deviceId) != null) {
          try {
            print('   Attempting to use CustomCameraController...');
            _customController = CustomCameraController();
            await _customController!.initialize(deviceId);
            _useCustomController = true;
            print('   ✅ CustomCameraController initialized successfully');
            print('   Active device: ${_customController!.currentDeviceId}');
            return;
          } catch (e) {
            print('   ⚠️ CustomCameraController failed: $e');
            print('   Falling back to standard CameraController...');
            _customController = null;
            _useCustomController = false;
            // Continue with standard controller initialization
          }
        }
      }

      // Find exact camera match from available cameras
      CameraDescription? cameraToUse;

      // Strategy 1: Try exact name match first
      cameraToUse = _cameras!.firstWhere(
        (c) => c.name == camera.name,
        orElse: () => const CameraDescription(
          name: '',
          lensDirection: CameraLensDirection.external,
          sensorOrientation: 0,
        ),
      );

      // Strategy 2: If no exact match, try to match by device ID
      if (cameraToUse.name.isEmpty && camera.name.contains(':')) {
        final deviceId = camera.name.split(':').last.split(',').first;
        cameraToUse = _cameras!.firstWhere(
          (c) => c.name.contains(':$deviceId'),
          orElse: () => camera, // Use the provided camera as fallback
        );
      }

      // If still no match, use the provided camera
      if (cameraToUse.name.isEmpty) {
        cameraToUse = camera;
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
