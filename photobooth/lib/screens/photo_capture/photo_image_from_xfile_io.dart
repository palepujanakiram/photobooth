import 'dart:io' show File;
import 'package:flutter/material.dart';
import 'package:cross_file/cross_file.dart';

/// Builds an Image widget from XFile for mobile (io). Uses Image.file for immediate display.
/// Uses high filter quality so the captured photo stays sharp when scaled to fit the screen.
Widget imageFromXFile(XFile file) {
  return Image.file(
    File(file.path),
    fit: BoxFit.contain,
    gaplessPlayback: true,
    filterQuality: FilterQuality.high,
  );
}

/// Same as [imageFromXFile] but with explicit width/height. [fit] defaults to [BoxFit.contain];
/// use [BoxFit.cover] when the photo aspect (e.g. landscape webcam) differs from a portrait card.
Widget imageFromXFileSized(
  XFile file,
  double width,
  double height, {
  BoxFit fit = BoxFit.contain,
  Alignment alignment = Alignment.center,
}) {
  return Image.file(
    File(file.path),
    width: width,
    height: height,
    fit: fit,
    alignment: alignment,
    gaplessPlayback: true,
    filterQuality: FilterQuality.high,
  );
}
