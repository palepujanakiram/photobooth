import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform, kIsWeb;

/// Helper function to check if running on Android
bool get _isAndroid {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.android;
}

class AndroidCameraDeviceHelper {
  static const MethodChannel _channel =
      MethodChannel('com.example.photobooth/camera_device_helper');

  /// Gets all available cameras from Android using Camera2 API
  /// Returns a list of camera info maps, or null if not on Android or error occurs
  static Future<List<Map<String, dynamic>>?> getAllAvailableCameras() async {
    if (!_isAndroid) {
      print('⚠️ getAllAvailableCameras called on non-Android platform');
      return null;
    }

    try {
      final result = await _channel.invokeMethod('getAllAvailableCameras');
      if (result is List) {
        return result.cast<Map<dynamic, dynamic>>().map((map) {
          return Map<String, dynamic>.from(map);
        }).toList();
      }
      return null;
    } on PlatformException catch (e) {
      print('❌ Error getting Android cameras: ${e.message}');
      return null;
    } catch (e) {
      print('❌ Unexpected error getting Android cameras: $e');
      return null;
    }
  }
}

