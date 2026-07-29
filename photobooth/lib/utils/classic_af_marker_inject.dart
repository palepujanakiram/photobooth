import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image/image.dart' as img;

import '../services/file_helper.dart';
import 'logger.dart';

/// Burns in Canon-like white AF L-brackets + center focus box for scrub testing.
///
/// Admin-only (`injectAfMarkers`). Fail-open: returns [source] unchanged on error.
Future<XFile> injectClassicAfMarkers(XFile source) async {
  try {
    final bytes = await source.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return source;

    final framed = img.bakeOrientation(decoded);
    _drawAfOverlay(framed);

    final out = Uint8List.fromList(
      img.encodeJpg(framed, quality: 97),
    );
    if (kIsWeb) {
      return XFile.fromData(
        out,
        mimeType: 'image/jpeg',
        name: 'af_inject_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
    }
    try {
      final tempDir = await FileHelper.getTempDirectoryPath();
      const photosSubdir = 'photos';
      final photosDir = '$tempDir/$photosSubdir';
      await FileHelper.ensureDirectory(photosDir);
      final savePath =
          '$photosDir/af_inject_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final file = FileHelper.createFile(savePath);
      await (file as dynamic).writeAsBytes(out);
      return XFile((file as dynamic).path, mimeType: 'image/jpeg');
    } catch (_) {
      // Unit tests / restricted FS — still return in-memory JPEG with overlays.
      return XFile.fromData(
        out,
        mimeType: 'image/jpeg',
        name: 'af_inject_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
    }
  } catch (e, st) {
    AppLogger.warning(
      'AF marker inject failed; keeping original still',
      error: e,
      stackTrace: st,
    );
    return source;
  }
}

void _drawAfOverlay(img.Image image) {
  final w = image.width;
  final h = image.height;
  if (w < 32 || h < 32) return;

  final white = img.ColorRgb8(255, 255, 255);
  final thickness = (w / 420).clamp(2, 6).round();
  final inset = (w * 0.08).round().clamp(8, w ~/ 5);
  final arm = (w * 0.09).round().clamp(16, w ~/ 4);

  // Four corner L-brackets (viewfinder crop marks).
  _drawL(image, inset, inset, arm, arm, thickness, white, topLeft: true);
  _drawL(
    image,
    w - inset - 1,
    inset,
    arm,
    arm,
    thickness,
    white,
    topRight: true,
  );
  _drawL(
    image,
    inset,
    h - inset - 1,
    arm,
    arm,
    thickness,
    white,
    bottomLeft: true,
  );
  _drawL(
    image,
    w - inset - 1,
    h - inset - 1,
    arm,
    arm,
    thickness,
    white,
    bottomRight: true,
  );

  // Center face AF box (upper-middle, like Canon face tracking).
  final boxW = (w * 0.22).round().clamp(24, w ~/ 2);
  final boxH = (h * 0.18).round().clamp(24, h ~/ 2);
  final boxLeft = (w - boxW) ~/ 2;
  final boxTop = (h * 0.28).round().clamp(0, h - boxH - 1);
  _drawRect(image, boxLeft, boxTop, boxW, boxH, thickness, white);
  // Inner parallel tick (double-line AF look).
  final gap = (thickness + 2).clamp(2, 8);
  if (boxW > gap * 4 && boxH > gap * 4) {
    _drawRect(
      image,
      boxLeft + gap,
      boxTop + gap,
      boxW - gap * 2,
      boxH - gap * 2,
      thickness,
      white,
    );
  }
}

void _drawL(
  img.Image image,
  int x,
  int y,
  int armX,
  int armY,
  int thickness,
  img.ColorRgb8 color, {
  bool topLeft = false,
  bool topRight = false,
  bool bottomLeft = false,
  bool bottomRight = false,
}) {
  if (topLeft) {
    _hLine(image, x, x + armX, y, thickness, color);
    _vLine(image, x, y, y + armY, thickness, color);
  } else if (topRight) {
    _hLine(image, x - armX, x, y, thickness, color);
    _vLine(image, x, y, y + armY, thickness, color);
  } else if (bottomLeft) {
    _hLine(image, x, x + armX, y, thickness, color);
    _vLine(image, x, y - armY, y, thickness, color);
  } else if (bottomRight) {
    _hLine(image, x - armX, x, y, thickness, color);
    _vLine(image, x, y - armY, y, thickness, color);
  }
}

void _drawRect(
  img.Image image,
  int left,
  int top,
  int width,
  int height,
  int thickness,
  img.ColorRgb8 color,
) {
  final right = left + width - 1;
  final bottom = top + height - 1;
  _hLine(image, left, right, top, thickness, color);
  _hLine(image, left, right, bottom, thickness, color);
  _vLine(image, left, top, bottom, thickness, color);
  _vLine(image, right, top, bottom, thickness, color);
}

void _hLine(
  img.Image image,
  int x0,
  int x1,
  int y,
  int thickness,
  img.ColorRgb8 color,
) {
  final lo = x0 < x1 ? x0 : x1;
  final hi = x0 < x1 ? x1 : x0;
  for (var t = 0; t < thickness; t++) {
    final yy = y + t;
    if (yy < 0 || yy >= image.height) continue;
    for (var x = lo; x <= hi; x++) {
      if (x < 0 || x >= image.width) continue;
      image.setPixel(x, yy, color);
    }
  }
}

void _vLine(
  img.Image image,
  int x,
  int y0,
  int y1,
  int thickness,
  img.ColorRgb8 color,
) {
  final lo = y0 < y1 ? y0 : y1;
  final hi = y0 < y1 ? y1 : y0;
  for (var t = 0; t < thickness; t++) {
    final xx = x + t;
    if (xx < 0 || xx >= image.width) continue;
    for (var y = lo; y <= hi; y++) {
      if (y < 0 || y >= image.height) continue;
      image.setPixel(xx, y, color);
    }
  }
}
