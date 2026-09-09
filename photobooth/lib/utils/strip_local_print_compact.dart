import 'dart:typed_data';

import 'image_helper.dart';
import 'png_ihdr_peek.dart';
import 'strip_compositor_local.dart';

/// Drop overlays larger than this if Skia compact fails — dart-image decode of
/// a print-resolution PNG OOMs 4GB Android TV during "Preparing print match…".
const int kLocalOverlayIsolateMaxBytes = 2 * 1024 * 1024;

/// Skia-downscale capture plates before the local compose isolate.
///
/// Dart `image` JPEG decode of full Canon stills is what made DPS Continue
/// sit on "Building your strip…" for 30–40s. 1-shot samples to the 4×6 sheet;
/// 3-/4-shot samples to [kLocalStripCellJpegMaxLongEdge] (one 2×6 cell).
Future<List<Uint8List>> compactJpegsForLocalStripPrint(
  List<Uint8List> shots, {
  int maxLongEdge = kLocalPrintJpegMaxLongEdge,
  Future<Uint8List> Function(Uint8List shot)? downscale,
}) async {
  if (shots.isEmpty) return shots;
  final resize = downscale ??
      (shot) => _downscaleForLocalStrip(shot, maxLongEdge: maxLongEdge);
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

Future<Uint8List> _downscaleForLocalStrip(
  Uint8List shot, {
  required int maxLongEdge,
}) {
  return ImageHelper.downscaleJpegBytesToMaxLongEdge(
    shot,
    maxLongEdge: maxLongEdge,
    jpegQuality: kStripCapturedPhotoJpegQuality,
  );
}

/// Skia-resize an occasion overlay to the print sheet before dart-image.
///
/// Fail-open: keep a small PNG; drop a huge PNG so the isolate cannot allocate
/// a full-resolution RGBA buffer on 4GB TV boxes.
Future<LocalStripOverlay?> compactOverlayForLocalStripPrint(
  LocalStripOverlay? overlay, {
  required bool single,
  required bool landscape,
  Future<Uint8List> Function(Uint8List bytes, int width, int height)? resize,
}) async {
  if (overlay == null || overlay.pngBytes.isEmpty) return overlay;
  final dest = localStripOverlayDestSize(single: single, landscape: landscape);
  final peeked = peekPngIhhrDimensions(overlay.pngBytes);
  if (peeked != null &&
      peeked.width <= dest.width &&
      peeked.height <= dest.height) {
    return overlay;
  }
  try {
    final scaled = await (resize ?? _skiaResizeOverlay)(
      overlay.pngBytes,
      dest.width,
      dest.height,
    );
    if (scaled.isEmpty) return _overlayIfIsolateSafe(overlay);
    return LocalStripOverlay(pngBytes: scaled, slots: overlay.slots);
  } catch (_) {
    return _overlayIfIsolateSafe(overlay);
  }
}

Future<Uint8List> _skiaResizeOverlay(Uint8List bytes, int width, int height) {
  return ImageHelper.resizeImageBytesToPng(
    bytes: bytes,
    width: width,
    height: height,
  );
}

LocalStripOverlay? _overlayIfIsolateSafe(LocalStripOverlay overlay) {
  if (overlay.pngBytes.lengthInBytes <= kLocalOverlayIsolateMaxBytes) {
    return overlay;
  }
  return null;
}
