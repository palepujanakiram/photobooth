import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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
    img.encodeJpg(baked, quality: kCapturedPhotoJpegQuality),
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
