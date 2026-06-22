import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../services/file_helper.dart';
import '../../utils/uvc_capture_config.dart';

/// Grabs the pixels currently painted in [boundaryKey] (last visible preview frame).
Future<XFile?> rasterCaptureRepaintBoundary({
  required GlobalKey boundaryKey,
  double? pixelRatio,
  int maxLongEdge = UvcCaptureConfig.normalizeMaxDimension,
}) async {
  final context = boundaryKey.currentContext;
  if (context == null) return null;
  final renderObject = context.findRenderObject();
  if (renderObject is! RenderRepaintBoundary) return null;
  if (!renderObject.hasSize || renderObject.size.isEmpty) return null;

  final longEdge = math.max(renderObject.size.width, renderObject.size.height);
  final effectivePixelRatio = pixelRatio ??
      (longEdge <= 0 ? 1.0 : math.min(1.0, maxLongEdge / longEdge));

  final image = await renderObject.toImage(pixelRatio: effectivePixelRatio);
  try {
    final byteData =
        await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return null;
    final bytes = byteData.buffer.asUint8List();
    if (bytes.isEmpty) return null;

    final tempDir = await FileHelper.getTempDirectoryPath();
    const subdir = 'photos';
    final photosDir = '$tempDir/$subdir';
    await FileHelper.ensureDirectory(photosDir);
    final path =
        '$photosDir/uvc_raster_${DateTime.now().millisecondsSinceEpoch}.png';
    final file = FileHelper.createFile(path);
    await (file as dynamic).writeAsBytes(bytes);
    return XFile((file as dynamic).path);
  } finally {
    image.dispose();
  }
}
