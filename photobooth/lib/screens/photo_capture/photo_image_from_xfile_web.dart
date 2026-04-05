import 'package:flutter/material.dart';
import 'package:cross_file/cross_file.dart';

/// Builds an Image widget from XFile for web. Uses Image.network (blob URL).
/// Uses high filter quality so the captured photo stays sharp when scaled to fit the screen.
Widget imageFromXFile(XFile file) {
  return Image.network(
    file.path,
    fit: BoxFit.contain,
    gaplessPlayback: true,
    filterQuality: FilterQuality.high,
  );
}

/// Same as [imageFromXFile] but with explicit width/height. See io stub for [fit] / [alignment].
Widget imageFromXFileSized(
  XFile file,
  double width,
  double height, {
  BoxFit fit = BoxFit.contain,
  Alignment alignment = Alignment.center,
}) {
  return Image.network(
    file.path,
    width: width,
    height: height,
    fit: fit,
    alignment: alignment,
    gaplessPlayback: true,
    filterQuality: FilterQuality.high,
  );
}
