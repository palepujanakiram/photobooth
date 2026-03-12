import 'package:flutter/services.dart';
import 'camera_details.dart';

const MethodChannel _channel =
    MethodChannel('com.photobooth/camera_native_details');

/// Platform implementation using method channel (Android / iOS).
Future<CameraDetails?> getCameraDetails(String cameraId) async {
  try {
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      'getCameraDetails',
      cameraId,
    );
    if (result == null) return null;
    return CameraDetails.fromMap(result);
  } on PlatformException {
    return null;
  }
}
