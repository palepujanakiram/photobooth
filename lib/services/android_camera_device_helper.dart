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

  /// Forces Camera2 enumeration by waiting and checking repeatedly
  /// This can help when USB cameras take time to be enumerated
  /// Returns a map with 'found' (bool), 'camera2Id' (String?), and 'attempt' (int)
  static Future<Map<String, dynamic>?> forceCamera2Enumeration(
    int vendorId,
    int productId,
  ) async {
    if (!_isAndroid) {
      AppLogger.debug('⚠️ forceCamera2Enumeration called on non-Android platform');
      return null;
    }

    try {
      final result = await _channel.invokeMethod('forceCamera2Enumeration', {
        'vendorId': vendorId,
        'productId': productId,
      });
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return null;
    } on PlatformException catch (e) {
      AppLogger.debug('❌ Error forcing Camera2 enumeration: ${e.message}');
      return null;
    } catch (e) {
      AppLogger.debug('❌ Unexpected error forcing Camera2 enumeration: $e');
      return null;
    }
  }

  /// Gets USB vendor/product IDs for a given Camera2 ID
  /// Returns a map with 'vendorId' and 'productId, or null if not found
  static Future<Map<String, dynamic>?> getUsbIdsForCameraId(String cameraId) async {
    if (!_isAndroid) {
      AppLogger.debug('⚠️ getUsbIdsForCameraId called on non-Android platform');
      return null;
    }

    try {
      final result = await _channel.invokeMethod('getUsbIdsForCameraId', {
        'cameraId': cameraId,
      });
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return null;
    } on PlatformException catch (e) {
      AppLogger.debug('❌ Error getting USB IDs for camera ID: ${e.message}');
      return null;
    } catch (e) {
      AppLogger.debug('❌ Unexpected error getting USB IDs for camera ID: $e');
      return null;
    }
  }

  /// Requests USB permission proactively for a connected camera
  /// Returns a map with 'success' (bool) and 'alreadyGranted' (bool)
  static Future<Map<String, dynamic>?> requestUsbPermission(int vendorId, int productId) async {
    if (!_isAndroid) {
      AppLogger.debug('⚠️ requestUsbPermission called on non-Android platform');
      return null;
    }

    try {
      final result = await _channel.invokeMethod('requestUsbPermission', {
        'vendorId': vendorId,
        'productId': productId,
      });
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return null;
    } on PlatformException catch (e) {
      AppLogger.debug('❌ Error requesting USB permission: ${e.message}');
      return null;
    } catch (e) {
      AppLogger.debug('❌ Unexpected error requesting USB permission: $e');
      return null;
    }
  }
}

