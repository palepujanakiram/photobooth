import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;

/// Converts a YUV420 [CameraImage] into JPEG bytes (runs in an isolate).
Uint8List cameraImageToJpegBytes(CameraImage image) {
  if (image.planes.length < 3) {
    throw Exception('Unexpected CameraImage planes: ${image.planes.length}');
  }
  final width = image.width;
  final height = image.height;
  final yPlane = image.planes[0];
  final uPlane = image.planes[1];
  final vPlane = image.planes[2];

  final yBytes = yPlane.bytes;
  final uBytes = uPlane.bytes;
  final vBytes = vPlane.bytes;

  final yRowStride = yPlane.bytesPerRow;
  final uRowStride = uPlane.bytesPerRow;
  final vRowStride = vPlane.bytesPerRow;
  final uPixelStride = uPlane.bytesPerPixel ?? 1;
  final vPixelStride = vPlane.bytesPerPixel ?? 1;

  final out = img.Image(width: width, height: height);

  int clampChannel(int v) {
    if (v < 0) return 0;
    if (v > 255) return 255;
    return v;
  }

  for (int y = 0; y < height; y++) {
    final yRowOffset = yRowStride * y;
    final uRowOffset = uRowStride * (y >> 1);
    final vRowOffset = vRowStride * (y >> 1);
    for (int x = 0; x < width; x++) {
      final yIndex = yRowOffset + x;
      final uIndex = uRowOffset + (x >> 1) * uPixelStride;
      final vIndex = vRowOffset + (x >> 1) * vPixelStride;

      final yVal = yBytes[yIndex] & 0xFF;
      final uVal = (uBytes[uIndex] & 0xFF) - 128;
      final vVal = (vBytes[vIndex] & 0xFF) - 128;

      final r = (yVal + 1.402 * vVal).round();
      final g = (yVal - 0.344136 * uVal - 0.714136 * vVal).round();
      final b = (yVal + 1.772 * uVal).round();

      out.setPixelRgb(x, y, clampChannel(r), clampChannel(g), clampChannel(b));
    }
  }

  return Uint8List.fromList(img.encodeJpg(out, quality: 85));
}
