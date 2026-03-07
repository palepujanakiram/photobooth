import 'package:flutter/material.dart';
import 'package:cross_file/cross_file.dart';

/// Builds an Image widget from XFile for web. Uses Image.network (blob URL).
Widget imageFromXFile(XFile file) {
  return Image.network(
    file.path,
    fit: BoxFit.contain,
    gaplessPlayback: true,
  );
}
