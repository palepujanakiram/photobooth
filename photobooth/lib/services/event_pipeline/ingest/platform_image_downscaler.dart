import 'package:flutter/services.dart';

import 'image_downscaler.dart';

/// [ImageDownscaler] backed by native `ImageDecoder` + `Bitmap.compress`.
///
/// The URI is handed straight to the platform, so a 6 MB original is decoded,
/// scaled and re-encoded natively and never crosses into the Dart heap. Only the
/// ~1.3 MB derivative comes back.
class PlatformImageDownscaler implements ImageDownscaler {
  PlatformImageDownscaler({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'com.srisarani.fotozenai/event_downscale';

  final MethodChannel _channel;

  @override
  Future<DownscaleResult> downscale({
    required String sourceUri,
    required int targetShortSide,
    int maxLongSide = DownscaleTarget.maxLongSide,
    int quality = DownscaleTarget.jpegQuality,
  }) async {
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'downscale',
      <String, Object?>{
        'uri': sourceUri,
        'targetShortSide': targetShortSide,
        'maxLongSide': maxLongSide,
        'quality': quality,
      },
    );
    final bytes = result?['bytes'];
    if (bytes is! Uint8List || bytes.isEmpty) {
      throw StateError('Downscale returned no image data for $sourceUri');
    }
    return DownscaleResult(
      bytes: bytes,
      width: _int(result?['width']) ?? 0,
      height: _int(result?['height']) ?? 0,
    );
  }

  static int? _int(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return null;
  }
}
