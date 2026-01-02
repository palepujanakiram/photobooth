import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;

/// Helper function to check if running on iOS
/// Works on all platforms including web
bool get _isIOS {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.iOS;
}

/// Helper class to communicate with native iOS code for camera device selection by device ID
/// This bypasses the Flutter camera package's direction-based matching
/// 
/// This class is iOS-specific and will return null/skip operations on Android and Web
class IOSCameraDeviceHelper {
  static const MethodChannel _channel = MethodChannel('com.photobooth/camera_device');
  
  /// Verifies that a camera device with the given device ID exists and is accessible
  /// Returns device info if found, null otherwise
  static Future<Map<String, dynamic>?> verifyCameraDevice(String deviceId) async {
    // Skip on Web
    if (kIsWeb) {
      return null;
    }
    
    // Skip on Android - only works on iOS
    if (!_isIOS) {
      return null;
    }
    
    try {
      final result = await _channel.invokeMethod('getCameraDeviceId', {
        'cameraName': 'com.apple.avfoundation.avcapturedevice.built-in_video:$deviceId',
      });
      
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      
      return null;
    } catch (e) {
      print('⚠️ Error verifying camera device: $e');
      return null;
    }
  }
  
  /// Initializes camera by device ID (bypasses lensDirection matching)
  /// This is the workaround for iOS selecting wrong camera when multiple cameras
  /// have the same lensDirection
  static Future<Map<String, dynamic>?> initializeCameraByDeviceId(String deviceId) async {
    // Skip on Web
    if (kIsWeb) {
      return null;
    }
    
    // Skip on Android - only works on iOS
    if (!_isIOS) {
      return null;
    }
    
    try {
      final result = await _channel.invokeMethod('initializeCameraByDeviceId', {
        'deviceId': deviceId,
      });
      
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      
      return null;
    } catch (e) {
      print('⚠️ Error initializing camera by device ID: $e');
      return null;
    }
  }
  
  /// Gets all currently available camera devices from iOS
  /// Returns a list of device info maps, or null if not on iOS
  static Future<List<Map<String, dynamic>>?> getAllAvailableCameras() async {
    // Skip on Web
    if (kIsWeb) {
      return null;
    }
    
    // Skip on Android - only works on iOS
    if (!_isIOS) {
      return null;
    }
    
    try {
      final result = await _channel.invokeMethod('getAllAvailableCameras');
      
      if (result is List) {
        return result.map((item) => Map<String, dynamic>.from(item as Map)).toList();
      }
      
      return null;
    } catch (e) {
      print('⚠️ Error getting available cameras: $e');
      return null;
    }
  }
}

