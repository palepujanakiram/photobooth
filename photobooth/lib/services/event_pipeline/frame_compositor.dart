import 'package:flutter/services.dart';

import '../../models/event_pipeline/event_print_size.dart';

class CompositeResult {
  const CompositeResult({
    required this.bytes,
    required this.width,
    required this.height,
    this.thumbBytes,
    this.thumbWidth,
    this.thumbHeight,
  });

  final Uint8List bytes;
  final int width;
  final int height;

  /// Grid thumbnail off the finished canvas, when one was asked for. This is
  /// what lets the queue show the framed result rather than the raw import.
  final Uint8List? thumbBytes;
  final int? thumbWidth;
  final int? thumbHeight;

  bool get hasThumb => thumbBytes != null && thumbBytes!.isNotEmpty;
}

/// Draws a photo and an optional frame onto the print raster.
abstract class FrameCompositor {
  /// Cover-fits [photoPath] onto a [size] canvas, then overlays [framePath].
  ///
  /// A null [framePath] still renders — that is how a frame-disabled item is
  /// normalised to the print raster without a second code path.
  /// Pass [thumbShortSide] to also get the grid thumbnail off the finished
  /// canvas. Zero skips it.
  Future<CompositeResult> composite({
    required String photoPath,
    required String? framePath,
    required EventPrintSize size,
    int quality = 88,
    int thumbShortSide = 0,
  });
}

/// [FrameCompositor] backed by native Canvas drawing.
///
/// Native rather than `package:image` for the same reason as the downscaler:
/// pure-Dart decode, composite and encode at print resolution runs into seconds
/// per image, which at 400 photos is the difference between minutes and an hour.
/// `strip_compositor_local.dart` is the pure-Dart precedent, but it works on a
/// 1200×1800 strip sheet and treats frames as background colours rather than
/// alpha overlays.
class PlatformFrameCompositor implements FrameCompositor {
  PlatformFrameCompositor({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'com.srisarani.fotozenai/event_frame';

  final MethodChannel _channel;

  @override
  Future<CompositeResult> composite({
    required String photoPath,
    required String? framePath,
    required EventPrintSize size,
    int quality = 88,
    int thumbShortSide = 0,
  }) async {
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'composite',
      <String, Object?>{
        'photoPath': photoPath,
        'framePath': framePath,
        'width': size.width,
        'height': size.height,
        'thumbShortSide': thumbShortSide,
        'quality': quality,
      },
    );
    final bytes = result?['bytes'];
    if (bytes is! Uint8List || bytes.isEmpty) {
      throw StateError('Composite returned no image data for $photoPath');
    }
    final thumb = result?['thumbBytes'];
    return CompositeResult(
      bytes: bytes,
      width: _int(result?['width']) ?? size.width,
      height: _int(result?['height']) ?? size.height,
      thumbBytes: thumb is Uint8List && thumb.isNotEmpty ? thumb : null,
      thumbWidth: _int(result?['thumbWidth']),
      thumbHeight: _int(result?['thumbHeight']),
    );
  }

  static int? _int(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return null;
  }
}
