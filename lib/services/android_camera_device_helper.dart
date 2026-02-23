import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform, kIsWeb;
import '../utils/logger.dart';

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
      AppLogger.debug('⚠️ getAllAvailableCameras called on non-Android platform');
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
      AppLogger.debug('❌ Error getting Android cameras: ${e.message}');
      return null;
    } catch (e) {
      AppLogger.debug('❌ Unexpected error getting Android cameras: $e');
      return null;
    }
  }

  /// Resolves a USB camera (by vendor/product ID) to a Camera2 ID at runtime.
  /// Returns the Camera2 ID string if the device is found and has a Camera2 ID, null otherwise.
  static Future<String?> resolveUsbToCamera2Id(int vendorId, int productId) async {
    if (!_isAndroid) return null;
    try {
      final result = await _channel.invokeMethod('resolveUsbToCamera2Id', {
        'vendorId': vendorId,
        'productId': productId,
      });
      if (result is String && result.isNotEmpty) return result;
      return null;
    } on PlatformException catch (e) {
      AppLogger.debug('❌ resolveUsbToCamera2Id error: ${e.message}');
      return null;
    } catch (e) {
      AppLogger.debug('❌ resolveUsbToCamera2Id: $e');
      return null;
    }
  }
}

