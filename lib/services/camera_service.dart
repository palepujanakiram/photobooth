import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart';
import '../utils/exceptions.dart' as app_exceptions;
import '../utils/constants.dart';
import '../utils/logger.dart';
import 'error_reporting/error_reporting_manager.dart';
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
    } catch (e, stackTrace) {
      AppLogger.debug('❌ Error requesting camera permission: $e');
      
      // Log to Bugsnag
      ErrorReportingManager.log('❌ Error requesting camera permission (iOS)');
      await ErrorReportingManager.recordError(
        e,
        stackTrace,
        reason: 'iOS camera permission request failed',
        extraInfo: {
          'error': e.toString(),
        },
      );
      
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
    } catch (e, stackTrace) {
      AppLogger.debug('❌ Error testing external cameras: $e');
      
      // Log to Bugsnag (non-fatal)
      ErrorReportingManager.log('⚠️ Error testing external cameras');
      await ErrorReportingManager.recordError(
        e,
        stackTrace,
        reason: 'testExternalCameras failed',
        extraInfo: {
          'error': e.toString(),
        },
        fatal: false,
      );
      
      return null;
    }
  }

  /// Refresh the camera list (useful after connection/disconnection)
  Future<void> refreshCameraList() async {
    AppLogger.debug('🔄 Refreshing camera list...');
    try {
      await getAvailableCameras();
      AppLogger.debug('✅ Camera list refreshed');
    } catch (e, stackTrace) {
      AppLogger.debug('❌ Error refreshing camera list: $e');
      
      // Log to Bugsnag (non-fatal)
      ErrorReportingManager.log('⚠️ Error refreshing camera list');
      await ErrorReportingManager.recordError(
        e,
        stackTrace,
        reason: 'refreshCameraList failed',
        extraInfo: {
          'error': e.toString(),
        },
        fatal: false,
      );
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

      AppLogger.debug('✅ Final camera list: ${_cameras!.length} camera(s)');
      for (int i = 0; i < _cameras!.length; i++) {
        final camera = _cameras![i];
        final displayName = getCameraDisplayName(camera);
        final isExternal = camera.lensDirection == CameraLensDirection.external;
        AppLogger.debug(
            '   ${i + 1}. ${isExternal ? "🔌" : "📷"} $displayName (${camera.lensDirection})');
      }
      AppLogger.debug('');

      return _cameras!;
    } catch (e, stackTrace) {
      AppLogger.debug('❌ Error getting available cameras: $e');
      
      // Log to Bugsnag
      ErrorReportingManager.log('❌ Error getting available cameras');
      await ErrorReportingManager.recordError(
        e,
        stackTrace,
        reason: 'getAvailableCameras failed',
        extraInfo: {
          'error': e.toString(),
          'platform': defaultTargetPlatform.name,
        },
      );
      
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
    } catch (e, stackTrace) {
      AppLogger.debug('❌ Error requesting camera permission: $e');
      
      // Log to Bugsnag
      ErrorReportingManager.log('❌ Error requesting camera permission (Android)');
      await ErrorReportingManager.recordError(
        e,
        stackTrace,
        reason: 'Android camera permission request failed',
        extraInfo: {
          'error': e.toString(),
        },
      );
      
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
          String deviceId;
          final nameMatch = RegExp(r'Camera\s*(\d+)').firstMatch(camera.name);
          if (nameMatch != null) {
            // Extract ID from "Camera X" format
            deviceId = nameMatch.group(1)!;
            AppLogger.debug(
                '   📋 Extracted device ID from "Camera X" format: $deviceId');
          } else {
            // Assume it's already a direct ID (e.g., "2", "5")
            deviceId = camera.name;
            AppLogger.debug(
                '   📋 Using camera name directly as device ID: $deviceId');
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
          } catch (e, stackTrace) {
            AppLogger.debug('   ❌ Native camera controller failed: $e');
            AppLogger.debug('   📚 Stack trace: $stackTrace');

            AppLogger.debug(
                '   ⚠️ Falling back to standard CameraController...');
            AppLogger.debug(
                '   ⚠️ WARNING: Standard controller may not work for external cameras!');
            
            // Log to Bugsnag
            ErrorReportingManager.log('❌ Native Android camera controller initialization failed');
            await ErrorReportingManager.recordError(
              e,
              stackTrace,
              reason: 'Android CustomCameraController initialization failed',
              extraInfo: {
                'device_id': deviceId,
                'camera_name': camera.name,
                'localized_name': getCameraDisplayName(camera),
                'error': e.toString(),
                'will_fallback': 'true',
              },
            );
            
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
    } catch (e, stackTrace) {
      AppLogger.debug('❌ Error initializing camera: $e');
      
      // Log to Bugsnag
      ErrorReportingManager.log('❌ Camera initialization failed in CameraService');
      await ErrorReportingManager.recordError(
        e,
        stackTrace,
        reason: 'CameraService initializeCamera failed',
        extraInfo: {
          'camera_name': camera.name,
          'camera_direction': camera.lensDirection.toString(),
          'use_custom_controller': _useCustomController,
          'error': e.toString(),
        },
      );
      
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

  /// Gets the texture ID for custom controller preview
  int? get textureId => _customController?.textureId;

  /// Takes a picture and returns the XFile (works on all platforms including web)
  Future<XFile> takePicture() async {
    AppLogger.debug('📸 CameraService.takePicture() called');
    AppLogger.debug('   _useCustomController: $_useCustomController');
    AppLogger.debug('   _customController != null: ${_customController != null}');
    
    ErrorReportingManager.log('📸 CameraService.takePicture() called');
    await ErrorReportingManager.setCustomKeys({
      'service_useCustomController': _useCustomController,
      'service_hasCustomController': _customController != null,
      'service_hasStandardController': _controller != null,
    });
    
    // If using custom controller, use it for photo capture
    if (_useCustomController && _customController != null) {
      AppLogger.debug('   Using custom controller for photo capture');
      AppLogger.debug('   isPreviewRunning: ${_customController!.isPreviewRunning}');
      
      ErrorReportingManager.log('Using custom controller for photo capture');
      
      if (!_customController!.isPreviewRunning) {
        final error = 'Camera preview not running';
        AppLogger.debug('❌ $error');
        ErrorReportingManager.log('❌ Preview not running');
        
        await ErrorReportingManager.recordError(
          Exception(error),
          StackTrace.current,
          reason: 'Custom controller preview not running',
        );
        
        throw app_exceptions.CameraException(error);
      }

      try {
        AppLogger.debug('📸 Calling customController.takePicture()...');
        ErrorReportingManager.log('Calling customController.takePicture()');
        final imagePath = await _customController!.takePicture();
        AppLogger.debug('✅ Photo captured at: $imagePath');
        ErrorReportingManager.log('✅ CameraService: Photo captured successfully');
        return XFile(imagePath);
      } catch (e, stackTrace) {
        final error = '${AppConstants.kErrorPhotoCapture}: $e';
        AppLogger.debug('❌ $error');
        AppLogger.debug('Stack trace: $stackTrace');
        
        ErrorReportingManager.log('❌ CameraService: Custom controller takePicture failed');
        await ErrorReportingManager.recordError(
          e,
          stackTrace,
          reason: 'Custom controller takePicture failed',
          extraInfo: {'original_error': e.toString()},
        );
        
        throw app_exceptions.CameraException(error);
      }
    }
    
    AppLogger.debug('   Using standard controller for photo capture');
    ErrorReportingManager.log('Using standard controller for photo capture');

    // Use standard controller
    if (_controller == null || !_controller!.value.isInitialized) {
      ErrorReportingManager.log('❌ Standard controller not initialized');
      throw app_exceptions.CameraException('Camera not initialized');
    }

    try {
      // Double-check camera is still initialized right before capture
      // This catches race conditions where camera was closed mid-flight
      if (!_controller!.value.isInitialized) {
        ErrorReportingManager.log('❌ Camera was closed before capture');
        await ErrorReportingManager.recordError(
          Exception('Camera closed before capture'),
          StackTrace.current,
          reason: 'Camera state changed to uninitialized before takePicture',
          extraInfo: {
            'controller_null': _controller == null,
            'value_initialized': _controller?.value.isInitialized ?? false,
          },
        );
        throw app_exceptions.CameraException('Camera was closed before capture could complete');
      }
      
      final XFile image = await _controller!.takePicture();
      ErrorReportingManager.log('✅ CameraService: Standard controller photo captured');
      return image;
    } catch (e, stackTrace) {
      final errorString = e.toString();
      final isCameraClosedError = errorString.contains('Camera is closed') || 
                                    errorString.contains('camera is closed') ||
                                    errorString.contains('CameraDeviceImpl.close');
      
      ErrorReportingManager.log('❌ CameraService: Standard controller takePicture failed');
      await ErrorReportingManager.recordError(
        e,
        stackTrace,
        reason: isCameraClosedError 
            ? 'Camera was closed during capture (race condition)'
            : 'Standard CameraController takePicture failed',
        extraInfo: {
          'error': errorString,
          'error_type': e.runtimeType.toString(),
          'is_camera_closed_error': isCameraClosedError,
          'controller_null': _controller == null,
          'controller_initialized': _controller?.value.isInitialized ?? false,
        },
      );
      
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
    _useCustomController = false;
  }
}
