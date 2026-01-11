import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart';
import '../utils/exceptions.dart' as app_exceptions;
import '../utils/constants.dart';
import '../utils/logger.dart';
import 'custom_camera_controller.dart';
import 'ios_camera_device_helper.dart';
import 'android_camera_device_helper.dart';
import 'android_uvc_camera_helper.dart';

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
  bool _useUvcController = false;
  int? _uvcTextureId;

  // Map camera names (unique IDs) to their localized names from iOS
  final Map<String, String> _cameraLocalizedNames = {};

  // Camera change callback
  Function(String event, Map<String, dynamic> cameraInfo)? onCameraChanged;
  Function(String deviceName)? onUvcDisconnected;

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

        AppLogger.debug('📱 Camera $event: $localizedName');
        AppLogger.debug('   UniqueID: $uniqueID');
        AppLogger.debug('   External: $isExternal');

        // Notify callback if set
        onCameraChanged?.call(event, cameraInfo);

        // Refresh camera list
        await refreshCameraList();
      }
    });

    AppLogger.debug('✅ Camera change listener set up');
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

      AppLogger.debug('📱 Camera permission status: $status');

      return status == 'authorized';
    } catch (e) {
      AppLogger.debug('❌ Error requesting camera permission: $e');
      return false;
    }
  }

  /// Test external camera detection (iOS only)
  Future<Map<String, dynamic>?> testExternalCameras() async {
    if (!_isIOS) {
      AppLogger.debug('⚠️ testExternalCameras is only available on iOS');
      return null;
    }

    try {
      final result = await _iosChannel.invokeMethod('testExternalCameras');
      final testInfo = Map<String, dynamic>.from(result);

      AppLogger.debug('🔍 External Camera Test Results:');
      AppLogger.debug('   Total devices: ${testInfo['totalDevices']}');
      AppLogger.debug('   Built-in devices: ${testInfo['builtInDevices']}');
      AppLogger.debug('   External devices: ${testInfo['externalDevices']}');

      final externalNames = testInfo['externalNames'] as List<dynamic>;
      if (externalNames.isNotEmpty) {
        AppLogger.debug('   External camera names:');
        for (final name in externalNames) {
          AppLogger.debug('     - $name');
        }
      }

      return testInfo;
    } catch (e) {
      AppLogger.debug('❌ Error testing external cameras: $e');
      return null;
    }
  }

  /// Refresh the camera list (useful after connection/disconnection)
  Future<void> refreshCameraList() async {
    AppLogger.debug('🔄 Refreshing camera list...');
    try {
      await getAvailableCameras();
      AppLogger.debug('✅ Camera list refreshed');
    } catch (e) {
      AppLogger.debug('❌ Error refreshing camera list: $e');
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

      // Store Flutter's original camera list for Android external camera verification
      final flutterOriginalCameras = List<CameraDescription>.from(_cameras!);

      // Debug: Log all detected cameras
      AppLogger.debug(
          '📷 Detected ${_cameras!.length} camera(s) from Flutter:');
      for (final camera in _cameras!) {
        AppLogger.debug(
            '  - Name: "${camera.name}", Direction: ${camera.lensDirection}');
      }
      AppLogger.debug('');

      // On Android, get cameras from native Camera2 API to detect USB cameras
      if (!_isIOS && !kIsWeb) {
        AppLogger.debug('🤖 Android platform detected');
        AppLogger.debug('📱 Flutter detected ${_cameras!.length} camera(s):');
        for (int i = 0; i < _cameras!.length; i++) {
          final camera = _cameras![i];
          final isExternal =
              camera.lensDirection == CameraLensDirection.external;
          AppLogger.debug('   ${i + 1}. Name: "${camera.name}"');
          AppLogger.debug('      Direction: ${camera.lensDirection}');
          AppLogger.debug('      External: $isExternal');
          AppLogger.debug(
              '      Sensor Orientation: ${camera.sensorOrientation}');
          AppLogger.debug('');
        }

        // Get cameras from Android Camera2 API (includes USB cameras)
        try {
          final androidCameras =
              await AndroidCameraDeviceHelper.getAllAvailableCameras();
          if (androidCameras != null && androidCameras.isNotEmpty) {
            AppLogger.debug(
                '📱 Android Camera2 API reports ${androidCameras.length} camera(s):');
            AppLogger.debug('');

            for (int i = 0; i < androidCameras.length; i++) {
              final androidCamera = androidCameras[i];
              final uniqueID =
                  androidCamera['uniqueID'] as String? ?? 'unknown';
              final localizedName =
                  androidCamera['localizedName'] as String? ?? 'unknown';

              // Check if this camera is external by matching with Flutter's camera list
              // External cameras on Android have CameraLensDirection.external
              // Flutter camera names on Android are like "Camera 0", "Camera 1", etc.
              // Native uniqueID is just "0", "1", etc., so we need to extract the number
              final matchingFlutterCamera = _cameras!.firstWhere(
                (c) {
                  // Try exact match first
                  if (c.name == uniqueID) return true;
                  // Try extracting number from Flutter camera name (e.g., "Camera 0" -> "0")
                  final flutterNameMatch =
                      RegExp(r'Camera\s*(\d+)').firstMatch(c.name);
                  if (flutterNameMatch != null) {
                    final flutterId = flutterNameMatch.group(1);
                    return flutterId == uniqueID;
                  }
                  return false;
                },
                orElse: () => const CameraDescription(
                  name: '',
                  lensDirection: CameraLensDirection.back,
                  sensorOrientation: 0,
                ),
              );

              final hasMatch = matchingFlutterCamera.name.isNotEmpty;

              // Check if camera is external by:
              // 1. Flutter camera has external lens direction, OR
              // 2. Localized name contains "External" or "USB" (for cameras not in Flutter list), OR
              // 3. Camera source is "usb" (USB cameras detected via USB Manager), OR
              // 4. Camera has USB vendor/product IDs (found via USB probing but now has Camera2 ID)
              final source = androidCamera['source'] as String? ?? 'camera2';
              final hasUsbIds = androidCamera['usbVendorId'] != null ||
                  androidCamera['usbProductId'] != null;
              final isExternalByFlutter = hasMatch &&
                  matchingFlutterCamera.lensDirection ==
                      CameraLensDirection.external;
              final isExternalByName =
                  localizedName.toLowerCase().contains('external') ||
                      localizedName.toLowerCase().contains('usb');
              final isExternalByUsb =
                  source == 'usb'; // USB cameras are always external
              final isExternalByUsbProbed =
                  hasUsbIds; // Camera found via USB probing (now has Camera2 ID)
              // Also check if camera ID is beyond typical built-in range (0, 1) - likely external
              final cameraIdInt = int.tryParse(uniqueID) ?? -1;
              final isExternalByHighId = !hasMatch && cameraIdInt > 1;
              final isExternal = isExternalByFlutter ||
                  isExternalByName ||
                  isExternalByUsb ||
                  isExternalByUsbProbed ||
                  isExternalByHighId;

              AppLogger.debug('  📷 Camera #${i + 1} Details:');
              AppLogger.debug('     Unique ID: $uniqueID');
              AppLogger.debug('     Name: "$localizedName"');
              AppLogger.debug('     Source: $source');
              AppLogger.debug('     Has USB IDs: $hasUsbIds');
              AppLogger.debug(
                  '     External: $isExternal (by Flutter: $isExternalByFlutter, by name: $isExternalByName, by USB: $isExternalByUsb, by USB probed: $isExternalByUsbProbed, by high ID: $isExternalByHighId)');
              AppLogger.debug('');

              // Store mapping for all cameras (not just external)
              if (localizedName != 'unknown' && localizedName.isNotEmpty) {
                // Try to match with Flutter camera by camera ID
                if (hasMatch) {
                  // Store mapping using Flutter's camera name as key
                  _cameraLocalizedNames[matchingFlutterCamera.name] =
                      localizedName;
                  AppLogger.debug(
                      '     💾 Stored mapping: ${matchingFlutterCamera.name} -> "$localizedName"');

                  // If this camera is detected as external but Flutter has wrong lensDirection, correct it
                  if (isExternal &&
                      matchingFlutterCamera.lensDirection !=
                          CameraLensDirection.external) {
                    AppLogger.debug(
                        '     ⚠️ Camera detected as external but Flutter has ${matchingFlutterCamera.lensDirection} - correcting...');

                    // Find and replace the camera in the list
                    final cameraIndex = _cameras!.indexWhere(
                        (c) => c.name == matchingFlutterCamera.name);
                    if (cameraIndex >= 0) {
                      // Replace with corrected camera - keep original name for UI matching, but fix lensDirection
                      // Store the Camera2 ID in localizedNames for native controller lookup
                      final correctedCamera = CameraDescription(
                        name: matchingFlutterCamera
                            .name, // Keep original name (e.g., "Camera 2") for UI matching
                        lensDirection:
                            CameraLensDirection.external, // Force external
                        sensorOrientation:
                            matchingFlutterCamera.sensorOrientation,
                      );
                      _cameras![cameraIndex] = correctedCamera;
                      // Store both mappings: Flutter name -> localized name, and Camera2 ID -> localized name
                      _cameraLocalizedNames[matchingFlutterCamera.name] =
                          localizedName;
                      _cameraLocalizedNames[uniqueID] =
                          localizedName; // Also store Camera2 ID mapping
                      AppLogger.debug(
                          '     ✅ Corrected camera: ${matchingFlutterCamera.name} -> external (Camera2 ID: $uniqueID)');
                      AppLogger.debug(
                          '     ℹ️ Will use native Android camera controller with ID: $uniqueID');
                    }
                  }
                } else {
                  // Camera not found in Flutter list - might be USB camera
                  AppLogger.debug(
                      '     ⚠️ Camera $uniqueID not found in Flutter camera list');
                  AppLogger.debug(
                      '     This might be a USB camera not detected by Flutter');

                  // If it's an external camera (detected by name), add it to the list
                  // Even if Flutter can't use it, we'll show it and handle the error gracefully
                  if (isExternal) {
                    // Check if we already added this camera (by uniqueID) to prevent duplicates
                    // Check both exact match and "Camera X" format
                    final alreadyAdded = _cameras!.any((c) {
                      // Exact match
                      if (c.name == uniqueID) return true;
                      // Check if Flutter camera name matches (e.g., "Camera 5" matches uniqueID "5")
                      final flutterNameMatch =
                          RegExp(r'Camera\s*(\d+)').firstMatch(c.name);
                      if (flutterNameMatch != null) {
                        return flutterNameMatch.group(1) == uniqueID;
                      }
                      return false;
                    });

                    if (alreadyAdded) {
                      AppLogger.debug(
                          '     ℹ️ External camera $uniqueID already in list, skipping duplicate');
                      _cameraLocalizedNames[uniqueID] = localizedName;
                      continue;
                    }

                    AppLogger.debug(
                        '     ➕ External camera detected (not in Flutter availableCameras):');
                    AppLogger.debug('        UniqueID: $uniqueID');
                    AppLogger.debug('        Name: $localizedName');

                    // Check if camera exists in Flutter's list
                    final cameraExistsInFlutter =
                        flutterOriginalCameras.any((c) {
                      // Try exact match
                      if (c.name == uniqueID) return true;
                      // Try extracting number from Flutter camera name
                      final flutterNameMatch =
                          RegExp(r'Camera\s*(\d+)').firstMatch(c.name);
                      if (flutterNameMatch != null) {
                        return flutterNameMatch.group(1) == uniqueID;
                      }
                      return false;
                    });

                    if (cameraExistsInFlutter) {
                      // Camera exists in Flutter's list - but it might have wrong lensDirection
                      AppLogger.debug(
                          '     ✅ External camera $uniqueID EXISTS in Flutter camera package');
                      AppLogger.debug(
                          '     ⚠️ Flutter may have wrong lensDirection - correcting it...');

                      // Find and replace the Flutter camera with corrected one
                      final existingCameraIndex = _cameras!.indexWhere(
                        (c) {
                          if (c.name == uniqueID) return true;
                          final flutterNameMatch =
                              RegExp(r'Camera\s*(\d+)').firstMatch(c.name);
                          if (flutterNameMatch != null) {
                            return flutterNameMatch.group(1) == uniqueID;
                          }
                          return false;
                        },
                      );

                      if (existingCameraIndex >= 0) {
                        final existingCamera = _cameras![existingCameraIndex];
                        AppLogger.debug(
                            '     📋 Found existing camera: ${existingCamera.name} (${existingCamera.lensDirection})');

                        // Replace with corrected camera that has external lensDirection
                        // Keep original name for UI matching, but fix lensDirection
                        final correctedCamera = CameraDescription(
                          name: existingCamera
                              .name, // Keep original name (e.g., "Camera 2") for UI matching
                          lensDirection:
                              CameraLensDirection.external, // Force external
                          sensorOrientation: existingCamera
                              .sensorOrientation, // Keep original orientation
                        );

                        _cameras![existingCameraIndex] = correctedCamera;
                        // Store both mappings: original name -> localized name, and Camera2 ID -> localized name
                        _cameraLocalizedNames[existingCamera.name] =
                            localizedName;
                        _cameraLocalizedNames[uniqueID] =
                            localizedName; // Also store Camera2 ID mapping
                        AppLogger.debug(
                            '     ✅ Replaced with corrected camera: ${existingCamera.name} -> external (Camera2 ID: $uniqueID)');
                        AppLogger.debug(
                            '     ℹ️ Will use native Android camera controller with ID: $uniqueID');
                      } else {
                        AppLogger.debug(
                            '     ⚠️ Camera found in Flutter list but not in _cameras - adding it');
                        final externalCamera = CameraDescription(
                          name: uniqueID,
                          lensDirection: CameraLensDirection.external,
                          sensorOrientation: 0,
                        );
                        _cameras!.add(externalCamera);
                        _cameraLocalizedNames[uniqueID] = localizedName;
                      }
                    } else {
                      // Camera doesn't exist in Flutter's list, but add it anyway
                      // We'll show it in the UI and handle the error when user tries to use it
                      AppLogger.debug(
                          '     ⚠️ External camera $uniqueID NOT in Flutter camera package');
                      AppLogger.debug(
                          '     ➕ Adding to list - will use native controller');

                      // Always use external direction for external cameras
                      // Use uniqueID directly as name (e.g., "5", "6") for native controller
                      final externalCamera = CameraDescription(
                        name:
                            uniqueID, // Use uniqueID directly (e.g., "5", "6")
                        lensDirection: CameraLensDirection.external,
                        sensorOrientation:
                            0, // Default orientation for external cameras
                      );

                      _cameras!.add(externalCamera);
                      _cameraLocalizedNames[uniqueID] = localizedName;
                      AppLogger.debug(
                          '     ✅ Added external camera to list: $uniqueID -> "$localizedName"');
                      AppLogger.debug(
                          '     ℹ️ Will use native Android camera controller for this camera');
                    }
                  } else {
                    // Still store the mapping in case it's added later
                    _cameraLocalizedNames[uniqueID] = localizedName;
                  }
                }
              }
            }
            AppLogger.debug('');

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
              AppLogger.debug(
                  '🔍 Found ${externalAndroidCameras.length} external camera(s) in Android:');
              for (final extCamera in externalAndroidCameras) {
                final uniqueID = extCamera['uniqueID'] as String? ?? 'unknown';
                final localizedName =
                    extCamera['localizedName'] as String? ?? 'unknown';
                final isInFlutterList =
                    _cameras!.any((c) => c.name == uniqueID);
                AppLogger.debug(
                    '   ${isInFlutterList ? "✅" : "❌"} $localizedName (ID: $uniqueID)');
                if (!isInFlutterList) {
                  AppLogger.debug(
                      '      ⚠️ This USB camera is not detected by Flutter camera package');
                }
              }
              AppLogger.debug('');
            }
          } else {
            AppLogger.debug(
                '⚠️ Could not get Android camera list from Camera2 API');
          }
        } catch (e) {
          AppLogger.debug('⚠️ Error getting Android cameras: $e');
        }
      }

      // On iOS, verify cameras actually exist using platform channel
      if (_isIOS) {
        try {
          final iosCameras =
              await IOSCameraDeviceHelper.getAllAvailableCameras();
          if (iosCameras != null && iosCameras.isNotEmpty) {
            AppLogger.debug(
                '📱 iOS reports ${iosCameras.length} actually available camera(s):');
            AppLogger.debug('');

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

              AppLogger.debug('  📷 Camera #${i + 1} Details:');
              AppLogger.debug(
                  '     Name: "$localizedName" (length: ${localizedName.length})');
              if (localizedName == 'unknown') {
                AppLogger.debug(
                    '     ⚠️  WARNING: localizedName not found in iOS response!');
                AppLogger.debug(
                    '     Available keys: ${iosCamera.keys.join(", ")}');
              }
              AppLogger.debug('     Unique ID: $uniqueID');
              AppLogger.debug('     External: $isExternal');
              if (!isExternal) {
                AppLogger.debug('     Device ID: $deviceId');
              }
              AppLogger.debug('');

              // Store mapping from camera name to localized name
              // Flutter camera package uses a name format like:
              // "com.apple.avfoundation.avcapturedevice.built-in_video:8"
              // or for external: UUID format

              // For external cameras with UUID uniqueID
              if (isExternal) {
                _cameraLocalizedNames[uniqueID] = localizedName;
                AppLogger.debug(
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
                  AppLogger.debug(
                      '     ⚠️ Flutter camera has wrong direction: ${matchingFlutterCamera.lensDirection}');
                  AppLogger.debug('     ✅ Correcting to: $correctDirection');

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
                  AppLogger.debug(
                      '     ✅ Corrected camera: ${correctedCamera.name} -> "$localizedName" (${correctedCamera.lensDirection})');
                } else {
                  // Direction is correct, just store the mapping
                  _cameraLocalizedNames[matchingFlutterCamera.name] =
                      localizedName;
                  AppLogger.debug(
                      '     💾 Stored mapping: ${matchingFlutterCamera.name} -> "$localizedName"');
                }
              } else {
                // Camera not found in Flutter's list
                if (isExternal) {
                  // For external cameras detected by iOS but not in Flutter's list,
                  // add them manually to the cameras list
                  AppLogger.debug(
                      '     ➕ Adding external camera to list (not in Flutter availableCameras):');
                  AppLogger.debug('        UniqueID: $uniqueID');
                  AppLogger.debug('        Name: $localizedName');

                  final externalCamera = CameraDescription(
                    name:
                        uniqueID, // Use uniqueID as the name for external cameras
                    lensDirection: CameraLensDirection.external,
                    sensorOrientation: 0, // Default orientation
                  );

                  _cameras!.add(externalCamera);
                  _cameraLocalizedNames[uniqueID] = localizedName;
                  AppLogger.debug(
                      '     ✅ Added external camera: $uniqueID -> "$localizedName"');
                } else {
                  AppLogger.debug(
                      '     ⚠️ Camera with uniqueID $uniqueID not found in Flutter camera list');
                }
              }
            }
            AppLogger.debug('');
          } else {
            AppLogger.debug('⚠️ Could not get iOS camera list');
          }
        } catch (e) {
          AppLogger.debug('⚠️ Error getting iOS cameras: $e');
        }
      }

      // Sort cameras: external cameras first, then built-in cameras (front, back)
      _cameras!.sort((a, b) {
        final aIsExternal = a.lensDirection == CameraLensDirection.external;
        final bIsExternal = b.lensDirection == CameraLensDirection.external;
        
        // External cameras come first
        if (aIsExternal && !bIsExternal) return -1;
        if (!aIsExternal && bIsExternal) return 1;
        
        // If both are external or both are built-in, maintain original order
        // For built-in cameras, prefer back then front
        if (!aIsExternal && !bIsExternal) {
          if (a.lensDirection == CameraLensDirection.back && 
              b.lensDirection == CameraLensDirection.front) return -1;
          if (a.lensDirection == CameraLensDirection.front && 
              b.lensDirection == CameraLensDirection.back) return 1;
        }
        
        return 0;
      });

      AppLogger.debug('✅ Final camera list (sorted - external first): ${_cameras!.length} camera(s)');
      for (int i = 0; i < _cameras!.length; i++) {
        final camera = _cameras![i];
        final displayName = getCameraDisplayName(camera);
        final isExternal = camera.lensDirection == CameraLensDirection.external;
        AppLogger.debug(
            '   ${i + 1}. ${isExternal ? "🔌" : "📷"} $displayName (${camera.lensDirection})');
      }
      AppLogger.debug('');

      return _cameras!;
    } catch (e) {
      AppLogger.debug('❌ Error getting available cameras: $e');
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
        AppLogger.debug('✅ Camera permission granted');
        return true;
      } else if (status.isDenied) {
        AppLogger.debug('❌ Camera permission denied');
        return false;
      } else if (status.isPermanentlyDenied) {
        AppLogger.debug('❌ Camera permission permanently denied');
        // You might want to open app settings here
        await openAppSettings();
        return false;
      }
      return false;
    } catch (e) {
      AppLogger.debug('❌ Error requesting camera permission: $e');
      return false;
    }
  }

  /// Initializes the camera with the selected camera
  Future<void> initializeCamera(CameraDescription camera) async {
    try {
      AppLogger.debug('🎥 Initializing camera: ${camera.name}');
      AppLogger.debug('   Direction: ${camera.lensDirection}');

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
      // Dispose UVC controller if exists
      if (_useUvcController) {
        await AndroidUvcCameraHelper.disposeUvcCamera();
        _useUvcController = false;
        _uvcTextureId = null;
      }

      // For external cameras, use native controller (iOS or Android)
      // This bypasses Flutter's camera package limitations
      if (camera.lensDirection == CameraLensDirection.external) {
        AppLogger.debug('   🔌 External camera detected');
        AppLogger.debug(
            '   🔍 Using native camera controller for direct Camera2/AVFoundation access...');

        // Extract device ID from camera name and try native controller
        if (_isIOS) {
          // iOS: Extract from format like "device:0" or UUID
          String? deviceId;
          if (camera.name.contains(':')) {
            deviceId = camera.name.split(':').last.split(',').first;
          } else {
            // Might be UUID format for external cameras
            deviceId = camera.name;
          }

          if (deviceId.isEmpty) {
            AppLogger.debug(
                '   ⚠️ Could not extract device ID from camera name: ${camera.name}');
            AppLogger.debug('   Falling back to standard CameraController...');
          } else {
            try {
              AppLogger.debug(
                  '   Attempting to use native camera controller...');
              AppLogger.debug('   Device ID: $deviceId');
              _customController = CustomCameraController();
              await _customController!.initialize(deviceId);
              _useCustomController = true;
              AppLogger.debug(
                  '   ✅ Native camera controller initialized successfully');
              AppLogger.debug(
                  '   Active device: ${_customController!.currentDeviceId}');
              return;
            } on app_exceptions.PermissionException catch (e) {
              // Permission errors should be rethrown, not fallback
              AppLogger.debug('   ❌ Permission error: $e');
              rethrow;
            } catch (e) {
              AppLogger.debug('   ⚠️ Native camera controller failed: $e');
              AppLogger.debug(
                  '   Falling back to standard CameraController...');
              _customController = null;
              _useCustomController = false;
            }
          }
        } else {
          // Android: Extract device ID from camera name
          // Camera name could be:
          // 1. Direct ID: "5", "6" (for manually added external cameras)
          // 2. Flutter format: "Camera 5", "Camera 6" (from Flutter's availableCameras)
          // 3. USB identifier: "usb_1008_1888" (USB cameras without Camera2 ID)
          String? deviceId;
          final nameMatch = RegExp(r'Camera\s*(\d+)').firstMatch(camera.name);
          if (nameMatch != null) {
            // Extract ID from "Camera X" format
            deviceId = nameMatch.group(1)!;
            AppLogger.debug(
                '   📋 Extracted device ID from "Camera X" format: $deviceId');
          } else {
            // Check if it's a USB identifier (starts with "usb_")
            if (camera.name.startsWith('usb_')) {
              AppLogger.debug(
                  '   ⚠️ USB camera detected without Camera2 ID: ${camera.name}');
              AppLogger.debug(
                  '   🔍 Attempting to probe for Camera2 ID at initialization time...');
              
              // Extract USB vendor/product IDs from camera name (format: usb_vendorId_productId)
              final usbIdMatch = RegExp(r'usb_(\d+)_(\d+)').firstMatch(camera.name);
              final usbVendorId = usbIdMatch?.group(1);
              final usbProductId = usbIdMatch?.group(2);
              
              // Try multiple times with delays (camera may need time to enumerate)
              bool foundCamera2Id = false;
              
              // First, try forcing Camera2 enumeration (waits up to 30 seconds)
              if (usbVendorId != null && usbProductId != null) {
                try {
                  AppLogger.debug('   🔄 Attempting to force Camera2 enumeration...');
                  final forceResult = await AndroidCameraDeviceHelper.forceCamera2Enumeration(
                    int.parse(usbVendorId),
                    int.parse(usbProductId),
                  );
                  
                  if (forceResult != null && forceResult['found'] == true) {
                    final camera2Id = forceResult['camera2Id'] as String?;
                    if (camera2Id != null && camera2Id.isNotEmpty) {
                      deviceId = camera2Id;
                      foundCamera2Id = true;
                      AppLogger.debug('   ✅ Found Camera2 ID via forced enumeration: $camera2Id');
                    }
                  }
                } catch (e) {
                  AppLogger.debug('   ⚠️ Error forcing enumeration: $e');
                }
              }
              
              // If forced enumeration didn't work, try regular probing
              if (!foundCamera2Id) {
                for (int attempt = 1; attempt <= 3; attempt++) {
                  AppLogger.debug('   🔄 Probe attempt $attempt/3...');
                  
                  if (attempt > 1) {
                    // Wait before retrying (give Android time to enumerate)
                    await Future.delayed(Duration(seconds: attempt * 2));
                  }
                  
                  try {
                    final androidCameras =
                        await AndroidCameraDeviceHelper.getAllAvailableCameras();
                    if (androidCameras != null) {
                      // Look for the USB camera and check if it now has a Camera2 ID
                      for (final androidCamera in androidCameras) {
                        final uniqueID = androidCamera['uniqueID'] as String? ?? '';
                        final source = androidCamera['source'] as String? ?? 'camera2';
                        final cameraVendorId = androidCamera['usbVendorId'];
                        final cameraProductId = androidCamera['usbProductId'];
                        final localizedName = androidCamera['localizedName'] as String? ?? '';
                        
                        // Check if this is our USB camera:
                        // 1. By Camera2 ID (not 0, 1, and not the USB identifier)
                        // 2. By USB vendor/product IDs if available
                        bool isOurCamera = false;
                        
                        if (source == 'camera2' && 
                            uniqueID != '0' && 
                            uniqueID != '1' &&
                            uniqueID != camera.name &&
                            !uniqueID.startsWith('usb_')) {
                          // Check if USB IDs match (if available)
                          if (usbVendorId != null && usbProductId != null &&
                              cameraVendorId != null && cameraProductId != null) {
                            if (cameraVendorId.toString() == usbVendorId &&
                                cameraProductId.toString() == usbProductId) {
                              isOurCamera = true;
                              AppLogger.debug(
                                  '   ✅ Found Camera2 ID by USB ID match: $uniqueID (vendor=$usbVendorId, product=$usbProductId)');
                            }
                          } else {
                            // No USB ID matching available, but it's an external camera with Camera2 ID
                            // This might be our camera - accept it if it's the only external one
                            final externalCameras = androidCameras.where((c) => 
                              c['source'] == 'camera2' && 
                              c['uniqueID'] != '0' && 
                              c['uniqueID'] != '1' &&
                              !(c['uniqueID'] as String).startsWith('usb_')
                            ).toList();
                            
                            if (externalCameras.length == 1) {
                              // Only one external camera - likely ours
                              isOurCamera = true;
                              AppLogger.debug(
                                  '   ✅ Found Camera2 ID (only external camera): $uniqueID for camera: $localizedName');
                            } else if (externalCameras.length > 1) {
                              // Multiple external cameras - try to match by checking if any have USB IDs that match
                              // Or use the first one if we can't match (better than nothing)
                              AppLogger.debug(
                                  '   💡 Found ${externalCameras.length} external cameras - will try first one: $uniqueID');
                              // Accept the first external camera as a candidate
                              isOurCamera = true;
                            }
                          }
                          
                          if (isOurCamera) {
                            deviceId = uniqueID;
                            foundCamera2Id = true;
                            break;
                          }
                        }
                      }
                    }
                    
                    if (foundCamera2Id) {
                      break; // Found it, exit retry loop
                    }
                  } catch (e) {
                    AppLogger.debug('   ⚠️ Error probing for Camera2 ID (attempt $attempt): $e');
                  }
                }
              }
              
              // If still no Camera2 ID found, try using system-only camera ID "2" directly
              // Even though it's marked as "system only", the native controller might be able to access it
              if (!foundCamera2Id) {
                AppLogger.debug('   💡 No Camera2 ID found via enumeration, trying system-only camera ID "2" directly...');
                // Try to use camera ID "2" directly - it exists but is marked as "system only"
                // The native controller might be able to access it even though we can't probe it
                deviceId = '2';
                foundCamera2Id = true;
                AppLogger.debug('   🎯 Will attempt to use camera ID "2" directly (system-only device)');
                AppLogger.debug('   ⚠️ This camera is marked as "system only" but we will try to access it');
              }
              
              // If still no Camera2 ID found, we can't use this camera
              // Note: deviceId might be "2" which is valid, so we only fail if it's still the USB identifier
              if (!foundCamera2Id || deviceId == null || deviceId.isEmpty || deviceId == camera.name || deviceId.startsWith('usb_')) {
                AppLogger.debug(
                    '   ❌ USB camera does not have a Camera2 ID and cannot be accessed');
                AppLogger.debug(
                    '   💡 The camera may need time to enumerate, or may not be supported');
                AppLogger.debug(
                    '   💡 Try: 1) Disconnect and reconnect the camera');
                AppLogger.debug(
                    '   💡      2) Wait a few seconds after connecting');
                AppLogger.debug(
                    '   💡      3) Check if the camera is UVC-compliant');
                throw app_exceptions.CameraException(
                    'External camera "${getCameraDisplayName(camera)}" is not accessible. '
                    'The camera may need time to initialize or may require additional setup. '
                    'Please try: 1) Disconnect and reconnect the camera, 2) Wait a few seconds, then try again.');
              }
            } else {
              // Assume it's already a direct Camera2 ID (e.g., "2", "5")
            deviceId = camera.name;
            AppLogger.debug(
                '   📋 Using camera name directly as device ID: $deviceId');
            }
          }

          AppLogger.debug('   🤖 Android external camera detected');
          AppLogger.debug('   📋 Camera name: ${camera.name}');
          AppLogger.debug('   🔢 Device ID to use: $deviceId');
          AppLogger.debug(
              '   📝 Localized name: ${getCameraDisplayName(camera)}');

          try {
            AppLogger.debug(
                '   🚀 Attempting to use native Android camera controller...');
            AppLogger.debug(
                '   🎯 Will initialize with device ID: "$deviceId"');
            _customController = CustomCameraController();
            await _customController!.initialize(deviceId);
            _useCustomController = true;
            AppLogger.debug(
                '   ✅ Native Android camera controller initialized successfully');
            AppLogger.debug(
                '   ✅ Active device ID: ${_customController!.currentDeviceId}');
            AppLogger.debug('   ✅ Texture ID: ${_customController!.textureId}');
            AppLogger.debug(
                '   ✅ Preview will use Texture widget with ID: ${_customController!.textureId}');
            return;
          } on app_exceptions.PermissionException catch (e) {
            // Permission errors should be rethrown, not fallback
            AppLogger.debug('   ❌ Permission error: $e');
            rethrow;
          } catch (e, stackTrace) {
            AppLogger.debug('   ❌ Native camera controller failed: $e');
            AppLogger.debug('   📚 Stack trace: $stackTrace');

            // If it's an external camera, try UVC direct access as fallback
            if (camera.lensDirection == CameraLensDirection.external) {
              AppLogger.debug(
                  '   ❌ External camera cannot be accessed via Camera2 API');
              AppLogger.debug(
                  '   🔄 Attempting UVC direct access as fallback...');
              
              int? usbVendorId;
              int? usbProductId;
              
              // Try to extract vendor/product IDs from camera name (format: usb_vendorId_productId)
              if (camera.name.startsWith('usb_')) {
                final usbIdMatch = RegExp(r'usb_(\d+)_(\d+)').firstMatch(camera.name);
                usbVendorId = usbIdMatch?.group(1) != null ? int.tryParse(usbIdMatch!.group(1)!) : null;
                usbProductId = usbIdMatch?.group(2) != null ? int.tryParse(usbIdMatch!.group(2)!) : null;
                AppLogger.debug('   📋 Extracted USB IDs from camera name: vendor=$usbVendorId, product=$usbProductId');
              }
              
              // If not found in name, try to get USB IDs from camera ID
              if (usbVendorId == null || usbProductId == null) {
                AppLogger.debug('   🔍 Camera name does not contain USB IDs, querying native side...');
                // Extract camera ID from name (could be "2", "Camera 2", etc.)
                String? cameraId;
                final nameMatch = RegExp(r'Camera\s*(\d+)').firstMatch(camera.name);
                if (nameMatch != null) {
                  cameraId = nameMatch.group(1);
                } else if (RegExp(r'^\d+$').hasMatch(camera.name)) {
                  cameraId = camera.name;
                } else if (RegExp(r'^\d+$').hasMatch(deviceId)) {
                  cameraId = deviceId;
                }
                
                if (cameraId != null) {
                  AppLogger.debug('   🔍 Querying USB IDs for camera ID: $cameraId');
                  final usbIds = await AndroidCameraDeviceHelper.getUsbIdsForCameraId(cameraId);
                  if (usbIds != null && usbIds['vendorId'] != null && usbIds['productId'] != null) {
                    usbVendorId = usbIds['vendorId'] as int?;
                    usbProductId = usbIds['productId'] as int?;
                    AppLogger.debug('   ✅ Found USB IDs from native side: vendor=$usbVendorId, product=$usbProductId');
                  } else {
                    AppLogger.debug('   ⚠️ No USB IDs found for camera ID: $cameraId');
                  }
                }
              }
              
              if (usbVendorId != null && usbProductId != null) {
                try {
                  AppLogger.debug('   🎯 Trying UVC direct access...');
                  AppLogger.debug('      Vendor ID: $usbVendorId, Product ID: $usbProductId');
                  
                  final uvcResult = await AndroidUvcCameraHelper.initializeUvcCamera(
                    usbVendorId,
                    usbProductId,
                  );
                  
                  AppLogger.debug('   📥 UVC initialization result received: $uvcResult');
                  
                  if (uvcResult != null && uvcResult['success'] == true) {
                    final textureId = uvcResult['textureId'] as int?;
                    AppLogger.debug('   📥 Texture ID from result: $textureId');
                    if (textureId != null) {
                      AppLogger.debug('   ✅ UVC camera initialized successfully!');
                      AppLogger.debug('   ✅ Texture ID: $textureId');
                      
                      // Store UVC texture ID and mark as using UVC
                      _uvcTextureId = textureId;
                      _useUvcController = true;
                      // Don't set _useCustomController = true for UVC - UVC has its own texture
                      
                      // Set up USB disconnection event listener
                      AndroidUvcCameraHelper.setEventListener((deviceName) {
                        AppLogger.debug('📎 USB camera disconnected: $deviceName');
                        // Clear UVC state
                        _useUvcController = false;
                        _uvcTextureId = null;
                        _useCustomController = false;
                        // Cancel event listener
                        AndroidUvcCameraHelper.cancelEventListener();
                        // Notify callback
                        onUvcDisconnected?.call(deviceName);
                      });
                      
                      // Start UVC preview
                      AppLogger.debug('   🎬 Starting UVC preview...');
                      final previewStarted = await AndroidUvcCameraHelper.startUvcPreview();
                      if (previewStarted) {
                        AppLogger.debug('   ✅ UVC preview started');
                        // Longer delay to ensure preview surface is fully ready and USB transfers are set up
                        // This matches the native delay (1500ms) to ensure the USB event thread is ready
                        // The USB event thread needs time to initialize all transfer buffers before processing
                        await Future.delayed(const Duration(milliseconds: 2000));
                        AppLogger.debug('   ✅ UVC preview ready (texture ID: $_uvcTextureId)');
                      } else {
                        AppLogger.debug('   ⚠️ UVC preview start returned false');
                        // Even if preview start returned false, the texture might still be valid
                        // Continue and let the UI check if textureId is available
                      }
                      
                      AppLogger.debug('   ✅ Using UVC camera for preview');
                      AppLogger.debug('   📋 Texture ID: $_uvcTextureId');
                      AppLogger.debug('   📋 Using UVC controller: $_useUvcController');
                      AppLogger.debug('   📋 _useCustomController: $_useCustomController');
                      return;
                    } else {
                      AppLogger.debug('   ⚠️ UVC initialization succeeded but textureId is null');
                    }
                  } else {
                    AppLogger.debug('   ⚠️ UVC initialization failed or returned null');
                    AppLogger.debug('   ⚠️ Result: $uvcResult');
                  }
                  
                  AppLogger.debug('   ⚠️ UVC initialization returned: $uvcResult');
                } catch (uvcError, uvcStackTrace) {
                  AppLogger.debug('   ❌ UVC direct access also failed: $uvcError');
                  AppLogger.debug('   📚 UVC Stack trace: $uvcStackTrace');
                }
              } else {
                AppLogger.debug('   ⚠️ Could not determine USB vendor/product IDs for external camera');
              }
              
              // If UVC also fails, throw error
              AppLogger.debug(
                  '   ❌ External camera cannot be accessed via Camera2 or UVC');
              throw app_exceptions.CameraException(
                  'External camera "${getCameraDisplayName(camera)}" is not accessible. '
                  'The camera may need a few moments to initialize or may require additional setup. '
                  'Please disconnect and reconnect the camera, then try again.');
            }

            AppLogger.debug(
                '   ⚠️ Falling back to standard CameraController...');
            AppLogger.debug(
                '   ⚠️ WARNING: Standard controller may not work for external cameras!');
            _customController?.dispose();
            _customController = null;
            _useCustomController = false;
            // Don't return - let it try standard controller (will likely fail)
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
      AppLogger.debug('   Available cameras in system:');
      for (var cam in _cameras!) {
        final isTarget = cam.name == camera.name;
        final deviceId = cam.name.contains(':')
            ? cam.name.split(':').last.split(',').first
            : 'unknown';
        AppLogger.debug(
            '     ${isTarget ? ">>> " : "    "}Device ID: $deviceId, Name: ${cam.name}, Direction: ${cam.lensDirection}${isTarget ? " <-- TARGET" : ""}');
      }

      // Create new controller with the specified camera
      AppLogger.debug('   Creating new controller for: ${cameraToUse.name}');
      AppLogger.debug('   Camera direction: ${cameraToUse.lensDirection}');
      AppLogger.debug(
          '   Camera sensor orientation: ${cameraToUse.sensorOrientation}');

      AppLogger.debug('   Creating CameraController with:');
      AppLogger.debug('     - Camera name: ${cameraToUse.name}');
      AppLogger.debug('     - Direction: ${cameraToUse.lensDirection}');
      AppLogger.debug(
          '     - Sensor orientation: ${cameraToUse.sensorOrientation}');

      _controller = CameraController(
        cameraToUse, // Use the exact match from system list
        ResolutionPreset.high,
        enableAudio: false,
      );

      AppLogger.debug('   Initializing CameraController...');
      AppLogger.debug('   This may take longer for external cameras...');

      // Initialize with timeout to catch any issues
      await _controller!.initialize().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Camera initialization timed out after 10 seconds');
        },
      );

      AppLogger.debug('   ✅ CameraController initialized');

      // Additional small delay after initialization to ensure camera is ready
      await Future.delayed(const Duration(milliseconds: 300));

      // Verify the controller is using the correct camera
      if (_controller != null) {
        final activeCamera = _controller!.description;
        AppLogger.debug('✅ Controller initialized successfully:');
        AppLogger.debug('   Active camera name: ${activeCamera.name}');
        AppLogger.debug(
            '   Active camera direction: ${activeCamera.lensDirection}');
        AppLogger.debug(
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

        AppLogger.debug('   Device ID comparison:');
        AppLogger.debug('     Requested device ID: $requestedDeviceId');
        AppLogger.debug('     Active device ID: $activeDeviceId');

        // The name (device ID) MUST match exactly - this is the only reliable identifier
        if (!nameMatches) {
          AppLogger.debug('');
          AppLogger.debug(
              '❌❌❌ CRITICAL ERROR: iOS selected the wrong camera! ❌❌❌');
          AppLogger.debug('');
          AppLogger.debug('   Requested:');
          AppLogger.debug('     Device ID: $requestedDeviceId');
          AppLogger.debug('     Name: ${cameraToUse.name}');
          AppLogger.debug('     Direction: ${cameraToUse.lensDirection}');
          AppLogger.debug('');
          AppLogger.debug('   Actually Selected:');
          AppLogger.debug('     Device ID: $activeDeviceId');
          AppLogger.debug('     Name: ${activeCamera.name}');
          AppLogger.debug('     Direction: ${activeCamera.lensDirection}');
          AppLogger.debug('');
          AppLogger.debug('   ⚠️ ROOT CAUSE:');
          AppLogger.debug(
              '   The Flutter camera package uses lensDirection to match cameras.');
          AppLogger.debug(
              '   When multiple cameras have the same lensDirection (front),');
          AppLogger.debug(
              '   iOS selects the first one it finds, not the one we requested.');
          AppLogger.debug('');
          AppLogger.debug(
              '   This is a FUNDAMENTAL LIMITATION of the Flutter camera package.');
          AppLogger.debug(
              '   It cannot force iOS to use a specific device ID when cameras');
          AppLogger.debug('   share the same lensDirection.');
          AppLogger.debug('');
          AppLogger.debug('   💡 POSSIBLE SOLUTIONS:');
          AppLogger.debug(
              '   1. Create a custom camera controller using platform channel');
          AppLogger.debug(
              '   2. Fork the Flutter camera package to support device ID selection');
          AppLogger.debug(
              '   3. Wait for Flutter camera package to add device ID support');
          AppLogger.debug(
              '   4. Use a different camera library that supports device ID selection');
          AppLogger.debug('');

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
          AppLogger.debug(
              '✅ Camera device ID verification passed - correct camera is active');
          if (!directionMatches) {
            AppLogger.debug(
                '   ⚠️ Note: Direction mismatch (${cameraToUse.lensDirection} vs ${activeCamera.lensDirection}), but device ID matches');
          }
        }
      }
    } catch (e) {
      AppLogger.debug('❌ Error initializing camera: $e');
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

  /// Checks if using UVC controller
  bool get isUsingUvcController => _useUvcController;

  /// Gets the texture ID for custom controller preview
  /// Returns UVC texture ID if using UVC, otherwise custom controller texture ID
  int? get textureId {
    if (_useUvcController && _uvcTextureId != null) {
      return _uvcTextureId;
    }
    return _customController?.textureId;
  }

  /// Takes a picture and returns the XFile (works on all platforms including web)
  Future<XFile> takePicture() async {
    // Use UVC controller if available
    if (_useUvcController) {
      try {
        AppLogger.debug('📸 Capturing photo from UVC camera...');
        final photoPath = await AndroidUvcCameraHelper.captureUvcPhoto();
        if (photoPath != null) {
          return XFile(photoPath);
        } else {
          throw app_exceptions.CameraException('Failed to capture photo from UVC camera');
        }
      } catch (e) {
        throw app_exceptions.CameraException('UVC photo capture error: $e');
      }
    }
    
    // If using custom controller, use it for photo capture
    if (_useCustomController && _customController != null) {
      if (!_customController!.isPreviewRunning) {
        throw app_exceptions.CameraException('Camera preview not running');
      }

      try {
        final imagePath = await _customController!.takePicture();
        return XFile(imagePath);
      } catch (e) {
        throw app_exceptions.CameraException(
            '${AppConstants.kErrorPhotoCapture}: $e');
      }
    }

    // Use standard controller
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
  Future<void> dispose() async {
    _controller?.dispose();
    _controller = null;
    await _customController?.dispose();
    _customController = null;
    
    // Dispose UVC camera if active
    if (_useUvcController) {
      await AndroidUvcCameraHelper.disposeUvcCamera();
      AndroidUvcCameraHelper.cancelEventListener();
      _useUvcController = false;
      _uvcTextureId = null;
    }
    
    _useCustomController = false;
  }
}
