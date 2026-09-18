import 'package:flutter/services.dart';

const _channel = MethodChannel('photobooth/jpeg_encode');

Future<Uint8List?> encodeRgbaToJpegNative({
  required Uint8List rgba,
  required int width,
  required int height,
  int quality = 92,
}) async {
  if (rgba.isEmpty || width <= 0 || height <= 0) return null;
  try {
    final result = await _channel.invokeMethod<Uint8List>('encodeRgba', {
      'rgba': rgba,
      'width': width,
      'height': height,
      'quality': quality,
    });
    if (result == null || result.isEmpty) return null;
    return result;
  } on MissingPluginException {
    return null;
  } catch (_) {
    return null;
  }
}
