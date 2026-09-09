import 'dart:typed_data';

import 'image_helper.dart';

/// Skia-downscale capture plates before the local compose isolate.
///
/// Dart `image` JPEG decode of full Canon stills is what made DPS Continue
/// sit on "Building your strip…" for 30–40s. Skia samples to print size first.
Future<List<Uint8List>> compactJpegsForLocalStripPrint(
  List<Uint8List> shots, {
  Future<Uint8List> Function(Uint8List shot)? downscale,
}) async {
  if (shots.isEmpty) return shots;
  final resize = downscale ?? _downscaleForLocalStrip;
  final out = <Uint8List>[];
  for (final shot in shots) {
    if (shot.isEmpty) return const [];
    try {
      out.add(await resize(shot));
    } catch (_) {
      out.add(shot);
    }
  }
  return out;
}

Future<Uint8List> _downscaleForLocalStrip(Uint8List shot) {
  return ImageHelper.downscaleJpegBytesToMaxLongEdge(
    shot,
    maxLongEdge: kStripCapturedPhotoMaxDimension,
    jpegQuality: kStripCapturedPhotoJpegQuality,
  );
}
