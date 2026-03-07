import 'dart:io' show File;
import 'package:flutter/material.dart';
import 'package:cross_file/cross_file.dart';

/// Builds an Image widget from XFile for mobile (io). Uses Image.file for immediate display.
Widget imageFromXFile(XFile file) {
  return Image.file(
    File(file.path),
    fit: BoxFit.contain,
    gaplessPlayback: true,
  );
}
