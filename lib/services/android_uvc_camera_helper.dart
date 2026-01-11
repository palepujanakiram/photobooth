import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform, kIsWeb;
import '../utils/logger.dart';

/// Callback type for USB disconnection events
typedef UvcDisconnectionCallback = void Function(String deviceName);

/// Helper function to check if running on Android
bool get _isAndroid {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.android;
}

/// UVC Camera information
class UvcCameraInfo {
  final int vendorId;
  final int productId;
  final String deviceName;
  final String productName;
  final bool hasPermission;

  UvcCameraInfo({
    required this.vendorId,
    required this.productId,
    required this.deviceName,
    required this.productName,
    required this.hasPermission,
  });

  factory UvcCameraInfo.fromMap(Map<dynamic, dynamic> map) {
    return UvcCameraInfo(
      vendorId: map['vendorId'] as int,
      productId: map['productId'] as int,
      deviceName: map['deviceName'] as String? ?? 'Unknown',
      productName: map['productName'] as String? ?? 'USB Camera',
      hasPermission: map['hasPermission'] as bool? ?? false,
    );
  }

  String get identifier => 'uvc_${vendorId}_$productId';

  @override
  String toString() => '$productName (vendor=$vendorId, product=$productId)';
}

class AndroidUvcCameraHelper {
  static const MethodChannel _channel =
      MethodChannel('com.example.photobooth/camera_device_helper');
  static const MethodChannel _uvcChannel =
      MethodChannel('com.photobooth/uvc_camera');
  static const EventChannel _uvcEventChannel =
      EventChannel('com.photobooth/uvc_camera_events');
  static StreamSubscription<dynamic>? _eventSubscription;

  /// Gets all available UVC cameras via USB enumeration
  /// Returns a list of UVC camera info, or null if not on Android or error occurs
  static Future<List<UvcCameraInfo>?> getUvcCameras() async {
    if (!_isAndroid) {
      AppLogger.debug('⚠️ getUvcCameras called on non-Android platform');
      return null;
    }

    try {
      final result = await _channel.invokeMethod('getUvcCameras');
      if (result is List) {
        return result
            .cast<Map<dynamic, dynamic>>()
            .map((map) => UvcCameraInfo.fromMap(map))
            .toList();
      }
      return null;
    } on PlatformException catch (e) {
      AppLogger.debug('❌ Error getting UVC cameras: ${e.message}');
      return null;
    } catch (e) {
      AppLogger.debug('❌ Unexpected error getting UVC cameras: $e');
      return null;
    }
  }

  /// Initializes a UVC camera by vendor and product ID
  /// Returns a map with 'success': true/false and 'textureId': int? if successful
  static Future<Map<String, dynamic>?> initializeUvcCamera(
      int vendorId, int productId) async {
    if (!_isAndroid) {
      AppLogger.debug('⚠️ initializeUvcCamera called on non-Android platform');
      return null;
    }

    try {
      AppLogger.debug('📞 Calling native initializeUvcCamera: vendor=$vendorId, product=$productId');
      AppLogger.debug('   Channel: $_uvcChannel');
      
      // Add timeout to prevent hanging if USB permission dialog doesn't appear
      final result = await _uvcChannel.invokeMethod('initializeUvcCamera', {
        'vendorId': vendorId,
        'productId': productId,
      }).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          AppLogger.debug('   ⏱️ UVC initialization timed out after 30 seconds');
          throw TimeoutException('UVC camera initialization timed out. USB permission dialog may not have appeared.');
        },
      );
      
      AppLogger.debug('   ✅ Native method returned: $result');
      
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      AppLogger.debug('   ⚠️ Result is not a Map, returning null');
      return null;
    } on PlatformException catch (e) {
      AppLogger.debug('❌ PlatformException initializing UVC camera: ${e.code} - ${e.message}');
      AppLogger.debug('   Details: ${e.details}');
      return null;
    } catch (e, stackTrace) {
      AppLogger.debug('❌ Unexpected error initializing UVC camera: $e');
      AppLogger.debug('   Stack trace: $stackTrace');
      return null;
    }
  }

  /// Starts UVC camera preview
  static Future<bool> startUvcPreview() async {
    if (!_isAndroid) {
      AppLogger.debug('⚠️ startUvcPreview called on non-Android platform');
      return false;
    }

    try {
      final result = await _uvcChannel.invokeMethod('startUvcPreview');
      if (result is Map) {
        return result['success'] as bool? ?? false;
      }
      return false;
    } on PlatformException catch (e) {
      AppLogger.debug('❌ Error starting UVC preview: ${e.message}');
      return false;
    } catch (e) {
      AppLogger.debug('❌ Unexpected error starting UVC preview: $e');
      return false;
    }
  }

  /// Captures a photo from UVC camera
  static Future<String?> captureUvcPhoto() async {
    if (!_isAndroid) {
      AppLogger.debug('⚠️ captureUvcPhoto called on non-Android platform');
      return null;
    }

    try {
      final result = await _uvcChannel.invokeMethod('captureUvcPhoto');
      if (result is Map) {
        return result['photoPath'] as String?;
      }
      return null;
    } on PlatformException catch (e) {
      AppLogger.debug('❌ Error capturing UVC photo: ${e.message}');
      return null;
    } catch (e) {
      AppLogger.debug('❌ Unexpected error capturing UVC photo: $e');
      return null;
    }
  }

  /// Disposes UVC camera
  static Future<bool> disposeUvcCamera() async {
    if (!_isAndroid) {
      AppLogger.debug('⚠️ disposeUvcCamera called on non-Android platform');
      return false;
    }

    try {
      final result = await _uvcChannel.invokeMethod('disposeUvcCamera');
      if (result is Map) {
        return result['success'] as bool? ?? false;
      }
      return false;
    } on PlatformException catch (e) {
      AppLogger.debug('❌ Error disposing UVC camera: ${e.message}');
      return false;
    } catch (e) {
      AppLogger.debug('❌ Unexpected error disposing UVC camera: $e');
      return false;
    }
  }

  /// Sets up event listener for UVC camera events (USB disconnection, etc.)
  static void setEventListener(UvcDisconnectionCallback? onDisconnected) {
    if (!_isAndroid) return;
    
    // Cancel existing subscription if any
    _eventSubscription?.cancel();
    
    if (onDisconnected != null) {
      _eventSubscription = _uvcEventChannel.receiveBroadcastStream().listen(
        (event) {
          if (event is Map) {
            final eventType = event['event'] as String?;
            if (eventType == 'usb_disconnected') {
              final deviceName = event['deviceName'] as String? ?? 'Unknown';
              AppLogger.debug('📎 USB camera disconnected: $deviceName');
              onDisconnected(deviceName);
            }
          }
        },
        onError: (error) {
          AppLogger.debug('❌ Error in UVC event stream: $error');
        },
      );
    }
  }

  /// Cancels the event listener
  static void cancelEventListener() {
    _eventSubscription?.cancel();
    _eventSubscription = null;
  }
}
