import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'native_jpeg_encode.dart';

/// RGBA8888 → JPEG. Uses Android [Bitmap.compress] when the channel is live,
/// otherwise dart-image (tests / iOS / web).
Future<Uint8List> encodeRgbaToJpeg({
  required Uint8List rgba,
  required int width,
  required int height,
  int quality = 92,
  Future<Uint8List?> Function({
    required Uint8List rgba,
    required int width,
    required int height,
    required int quality,
  })? nativeEncode,
  Uint8List Function({
    required Uint8List rgba,
    required int width,
    required int height,
    required int quality,
  })? dartEncode,
}) async {
  final q = quality.clamp(1, 100);
  final native = nativeEncode ?? encodeRgbaToJpegNative;
  try {
    final encoded = await native(
      rgba: rgba,
      width: width,
      height: height,
      quality: q,
    );
    if (encoded != null && encoded.isNotEmpty) return encoded;
  } catch (_) {
    // Fall through to dart-image.
  }
  final fallback = dartEncode ?? encodeRgbaToJpegDart;
  return fallback(rgba: rgba, width: width, height: height, quality: q);
}

Uint8List encodeRgbaToJpegDart({
  required Uint8List rgba,
  required int width,
  required int height,
  int quality = 92,
}) {
  final image = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: rgba.buffer,
    bytesOffset: rgba.offsetInBytes,
    rowStride: width * 4,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return Uint8List.fromList(img.encodeJpg(image, quality: quality.clamp(1, 100)));
}
