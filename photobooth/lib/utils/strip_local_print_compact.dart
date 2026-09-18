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
      if (_jpegFitsLocalPrint(shot, maxLongEdge)) {
        out.add(shot);
      } else {
        return const [];
      }
    }
  }
  return out;
}

/// Compact data-URL stills into print-sized JPEGs before Continue.
///
/// Sidecar / CameraX Classic does not hydrate PTP files, so without this
/// Continue still Skia-decodes 1920 plates on the 4GB TV.
Future<List<Uint8List>> compactLookPreviewFromDataUrls({
  required List<Uint8List> existing,
  required List<String> dataUrls,
  required int expectedCount,
  required bool single,
  Future<Uint8List?> Function(String source)? loadBytes,
  Future<List<Uint8List>> Function(
    List<Uint8List> shots, {
    int maxLongEdge,
  })? compact,
}) async {
  if (existing.length == expectedCount) return existing;
  if (dataUrls.length != expectedCount || expectedCount <= 0) return existing;
  final urls = List<String>.from(dataUrls);
  final load = loadBytes ?? (source) => loadLocalStripSourceBytes(source, null);
  final loaded = <Uint8List>[];
  for (final url in urls) {
    final bytes = await load(url);
    if (bytes == null || bytes.isEmpty) return existing;
    loaded.add(bytes);
  }
  final resized = compact == null
      ? await compactJpegsForLocalStripPrint(
          loaded,
          maxLongEdge: localStripPrintJpegMaxLongEdge(single: single),
        )
      : await compact(
          loaded,
          maxLongEdge: localStripPrintJpegMaxLongEdge(single: single),
        );
  return resized.length == expectedCount ? resized : existing;
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

bool _jpegFitsLocalPrint(Uint8List shot, int maxLongEdge) {
  final size = peekJpegSofDimensions(shot);
  if (size == null) return shot.lengthInBytes < 64 * 1024;
  return size.width <= maxLongEdge && size.height <= maxLongEdge;
}

/// Skia-resize an occasion overlay to the print sheet before dart-image.
///
/// If Skia cannot shrink an oversized PNG, drop it. A 2 MB file can still
/// decode to tens of MB of RGBA and OOM 4GB TVs in the compose isolate.
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
    if (scaled.isEmpty) return null;
    return LocalStripOverlay(pngBytes: scaled, slots: overlay.slots);
  } catch (_) {
    return null;
  }
}

// coverage:ignore-start
Future<Uint8List> _skiaResizeOverlay(Uint8List bytes, int width, int height) {
  return ImageHelper.resizeImageBytesToPng(
    bytes: bytes,
    width: width,
    height: height,
  );
}
// coverage:ignore-end
