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

/// Same as [imageFromXFile] but with explicit width/height so the image fills the given box (with contain).
Widget imageFromXFileSized(XFile file, double width, double height) {
  return Image.network(
    file.path,
    width: width,
    height: height,
    fit: BoxFit.contain,
    gaplessPlayback: true,
    filterQuality: FilterQuality.high,
  );
}
