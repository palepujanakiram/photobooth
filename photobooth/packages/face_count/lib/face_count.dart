import 'package:flutter/services.dart';

/// On-device face count via platform method channel (ML Kit on Android, Vision on iOS).
class FaceCount {
  FaceCount._();

  static const MethodChannel _channel =
      MethodChannel('com.photobooth/face_count');

  /// Returns detected face count, or 0 on failure / unsupported platforms.
  static Future<int> detectFaceCount(String imagePath) async {
    if (imagePath.isEmpty) return 0;
    try {
      final count = await _channel.invokeMethod<int>(
        'detectFaceCount',
        imagePath,
      );
      return count ?? 0;
    } on PlatformException {
      return 0;
    } on MissingPluginException {
      return 0;
    }
  }
}
