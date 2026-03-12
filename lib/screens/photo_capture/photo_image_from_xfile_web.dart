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
