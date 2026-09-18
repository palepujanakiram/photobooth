import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../models/strip_models.dart';
import 'encode_rgba_jpeg.dart';
import 'strip_compositor_local.dart';
import 'strip_look_color_matrices.dart';
import 'strip_photo_cell_layout.dart';

/// Skia bake of the Classic print sheet (decode + composite + native JPEG).
///
/// Replaces dart-image isolate encode on 4GB Android TV. Throws on failure so
/// [composeLocalStripSheet] can fall back to the isolate path.
Future<Uint8List> composeLocalStripSheetWithSkia({
  required List<Uint8List> sources,
  required String filterId,
  required String frameId,
  required bool single,
  required bool landscape,
  LocalStripOverlay? overlay,
}) async {
  final width =
      single && landscape ? kLocalStripSheetHeight : kLocalStripSheetWidth;
  final height =
      single && landscape ? kLocalStripSheetWidth : kLocalStripSheetHeight;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(
    recorder,
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
  );
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()
      ..color = _sheetFill(
        frameId: frameId,
        single: single,
        hasOverlay: overlay != null,
      ),
  );

  final photos = <ui.Image>[];
  ui.Image? overlayImage;
  try {
    for (final bytes in sources) {
      photos.add(await _decodeUiImage(bytes));
    }
    final photoPaint = _photoPaint(filterId);
    if (single) {
      _drawSingle(
        canvas,
        photos.single,
        photoPaint,
        width.toDouble(),
        height.toDouble(),
        frameId,
        overlay,
      );
    } else {
      _drawDual(
        canvas,
        photos,
        photoPaint,
        frameId,
        overlay,
      );
    }
    if (overlay != null) {
      overlayImage = await _decodeUiImage(overlay.pngBytes);
      _blitOverlay(
        canvas,
        overlayImage,
        sheetWidth: width.toDouble(),
        sheetHeight: height.toDouble(),
        single: single,
      );
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    try {
      final bd = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (bd == null) {
        throw StateError('Skia strip compose produced empty pixels');
      }
      return encodeRgbaToJpeg(
        rgba: bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes),
        width: width,
        height: height,
        quality: kLocalStripJpegQuality,
      );
    } finally {
      image.dispose();
    }
  } finally {
    for (final photo in photos) {
      photo.dispose();
    }
    overlayImage?.dispose();
  }
}

Paint _photoPaint(String filterId) {
  final paint = Paint()..filterQuality = FilterQuality.medium;
  if (stripLookNeedsMatrixBake(filterId)) {
    paint.colorFilter = ColorFilter.matrix(stripLookColorMatrixValues(filterId));
  }
  return paint;
}

Color _sheetFill({
  required String frameId,
  required bool single,
  required bool hasOverlay,
}) {
  if (single && hasOverlay) return const Color(0xFF121212);
  return stripPhotoCellLetterboxColor(frameId);
}

void _drawSingle(
  Canvas canvas,
  ui.Image photo,
  Paint paint,
  double width,
  double height,
  String frameId,
  LocalStripOverlay? overlay,
) {
  final hole = overlay != null
      ? occasionSinglePhotoHole(
          overlay.slots,
          landscape: width > height,
        )
      : resolveClassicSinglePhotoHole(
          hasOverlay: false,
          landscape: width > height,
          frameId: frameId,
        );
  final window = Rect.fromLTWH(
    hole.left * width,
    hole.top * height,
    hole.width * width,
    hole.height * height,
  );
  _drawContain(
    canvas,
    photo,
    window,
    paint,
    letterbox: stripPhotoCellLetterboxColor(frameId),
  );
}

void _drawDual(
  Canvas canvas,
  List<ui.Image> photos,
  Paint paint,
  String frameId,
  LocalStripOverlay? overlay,
) {
  const stripWidth =
      (kLocalStripSheetWidth - kLocalStripCenterGutter) / 2;
  const stripHeight = kLocalStripSheetHeight * 1.0;
  final offsets = <double>[0, stripWidth + kLocalStripCenterGutter];
  final slots = overlay != null && overlay.slots.length == photos.length
      ? overlay.slots
      : null;
  final cells = computeStripPhotoCellRects(
    frameId: frameId,
    stripWidth: stripWidth,
    stripHeight: stripHeight,
    shotCount: photos.length,
    templateSlots: slots,
  );
  for (final left in offsets) {
    canvas.save();
    canvas.translate(left, 0);
    for (var i = 0; i < photos.length && i < cells.length; i++) {
      _drawContain(
        canvas,
        photos[i],
        cells[i].rect,
        paint,
        letterbox: stripPhotoCellLetterboxColor(frameId),
      );
    }
    canvas.restore();
  }
}

void _blitOverlay(
  Canvas canvas,
  ui.Image overlay, {
  required double sheetWidth,
  required double sheetHeight,
  required bool single,
}) {
  final src = Rect.fromLTWH(
    0,
    0,
    overlay.width.toDouble(),
    overlay.height.toDouble(),
  );
  if (single) {
    canvas.drawImageRect(
      overlay,
      src,
      Rect.fromLTWH(0, 0, sheetWidth, sheetHeight),
      Paint(),
    );
    return;
  }
  const stripWidth =
      (kLocalStripSheetWidth - kLocalStripCenterGutter) / 2;
  for (final left in <double>[0, stripWidth + kLocalStripCenterGutter]) {
    canvas.drawImageRect(
      overlay,
      src,
      Rect.fromLTWH(left, 0, stripWidth, kLocalStripSheetHeight.toDouble()),
      Paint(),
    );
  }
}

void _drawContain(
  Canvas canvas,
  ui.Image photo,
  Rect window,
  Paint paint, {
  required Color letterbox,
}) {
  canvas.save();
  canvas.clipRect(window);
  canvas.drawRect(window, Paint()..color = letterbox);
  final dest = containFitDestination(
    sourceWidth: photo.width.toDouble(),
    sourceHeight: photo.height.toDouble(),
    window: window,
  );
  canvas.drawImageRect(
    photo,
    Rect.fromLTWH(0, 0, photo.width.toDouble(), photo.height.toDouble()),
    dest,
    paint,
  );
  canvas.restore();
}

Future<ui.Image> _decodeUiImage(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    final frame = await codec.getNextFrame();
    return frame.image;
  } finally {
    codec.dispose();
  }
}
