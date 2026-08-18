import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../utils/constants.dart';
import '../../utils/image_helper.dart';
import '../../utils/print_orientation.dart';
import '../../utils/print_size_helpers.dart';

/// Oriented pixel dimensions after EXIF bake (for DNP print-size inference).
typedef OrientedImageDimensions = ({int width, int height});

/// Reads JPEG/PNG dimensions with EXIF orientation applied.
OrientedImageDimensions? orientedDimensionsFromBytes(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final baked = img.bakeOrientation(decoded);
    return (width: baked.width, height: baked.height);
  } catch (_) {
    return null;
  }
}

/// Staff DNP: session/URL token first; for orientation-selectable sizes use image aspect.
String resolveStaffDnpPrintSize({
  required String imageUrl,
  String? stripCompositeUrl,
  String? single6x4Url,
  String? sessionPrintSize,
  int? classicComposeShotCount,
  OrientedImageDimensions? orientedDimensions,
}) {
  final fromSession = resolveStaffNetworkPrintSize(
    imageUrl: imageUrl,
    stripCompositeUrl: stripCompositeUrl,
    single6x4Url: single6x4Url,
    sessionPrintSize: sessionPrintSize,
    classicComposeShotCount: classicComposeShotCount,
  );

  if (!isOrientationSelectablePrintSize(fromSession)) {
    return fromSession;
  }
  if (orientedDimensions == null) {
    return fromSession;
  }

  final w = orientedDimensions.width;
  final h = orientedDimensions.height;
  if (w <= 0 || h <= 0) return fromSession;

  return PrintOrientation.fromContentAspect(w / h).printSize;
}

/// Paper width÷height for orientation-selectable DNP tokens (`s4x6` / `s6x4`).
double? networkPrintSizeAspectRatio(String networkPrintSize) {
  final token = networkPrintSize.trim().toLowerCase();
  if (token == AppConstants.kPrintSizePortrait4x6) return 4 / 6;
  if (token == AppConstants.kPrintSizeLandscape6x4) return 6 / 4;
  return null;
}

/// Letterbox [source] onto [targetAspect] (contain) so printers don't cover-crop
/// edge typography. Returns null when already matching within [tolerance].
@visibleForTesting
img.Image? letterboxImageToAspect(
  img.Image source,
  double targetAspect, {
  double tolerance = 0.02,
}) {
  if (!(targetAspect > 0)) return null;
  final current = source.width / source.height;
  if ((current - targetAspect).abs() / targetAspect <= tolerance) {
    return null;
  }

  late final int canvasW;
  late final int canvasH;
  if (current > targetAspect) {
    canvasW = source.width;
    canvasH = (source.width / targetAspect).round().clamp(1, 1 << 15);
  } else {
    canvasH = source.height;
    canvasW = (source.height * targetAspect).round().clamp(1, 1 << 15);
  }

  final canvas = img.Image(width: canvasW, height: canvasH);
  img.fill(canvas, color: img.ColorRgb8(0, 0, 0));
  final dx = ((canvasW - source.width) / 2).round();
  final dy = ((canvasH - source.height) / 2).round();
  img.compositeImage(canvas, source, dstX: dx, dstY: dy);
  return canvas;
}

/// EXIF-bake + letterbox onto the paper aspect for `s4x6` / `s6x4`.
Future<XFile> prepareImageForDnpPrint(
  XFile file, {
  required String networkPrintSize,
}) async {
  final oriented = await normalizeExifOrientationForDnpPrint(file);
  return letterboxImageToNetworkPrintSize(
    oriented,
    networkPrintSize,
  );
}

/// Contain-fit onto 4×6 / 6×4 paper canvas. No-ops for strip / unknown sizes.
Future<XFile> letterboxImageToNetworkPrintSize(
  XFile file,
  String networkPrintSize,
) async {
  final targetAspect = networkPrintSizeAspectRatio(networkPrintSize);
  if (targetAspect == null) return file;

  final bytes = await file.readAsBytes();
  if (bytes.isEmpty) return file;

  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    return file;
  }
  if (decoded == null) return file;

  final baked = img.bakeOrientation(decoded);
  final letterboxed = letterboxImageToAspect(baked, targetAspect);
  if (letterboxed == null) return file;

  return _writeNormalizedDnpPrintFile(letterboxed);
}

/// Writes a temp JPEG with EXIF orientation baked in (USB/WCM see upright pixels).
Future<XFile> normalizeExifOrientationForDnpPrint(XFile file) async {
  final bytes = await file.readAsBytes();
  if (bytes.isEmpty) return file;

  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    return file;
  }
  if (decoded == null) return file;

  final baked = img.bakeOrientation(decoded);
  return finalizeNormalizedDnpPrint(file, decoded, baked);
}

@visibleForTesting
Future<XFile> finalizeNormalizedDnpPrint(
  XFile file,
  img.Image decoded,
  img.Image baked,
) async {
  if (baked.width == decoded.width &&
      baked.height == decoded.height &&
      !_likelyExifRotated(decoded, baked)) {
    return file;
  }

  return _writeNormalizedDnpPrintFile(baked);
}

@visibleForTesting
Future<XFile> writeNormalizedDnpPrintFile(img.Image baked) async {
  return _writeNormalizedDnpPrintFile(baked);
}

Future<XFile> _writeNormalizedDnpPrintFile(img.Image baked) async {
  final encoded = Uint8List.fromList(
    img.encodeJpg(baked, quality: kDnpPrintJpegQuality),
  );
  final dir = await getTemporaryDirectory();
  final out = File(
    p.join(
      dir.path,
      'dnp_print_${DateTime.now().millisecondsSinceEpoch}.jpg',
    ),
  );
  await out.writeAsBytes(encoded, flush: true);
  return XFile(out.path);
}

bool _likelyExifRotated(img.Image decoded, img.Image baked) {
  return decoded.width != baked.width || decoded.height != baked.height;
}
