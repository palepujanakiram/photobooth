import 'dart:io' show File;
import 'package:flutter/material.dart';
import 'package:cross_file/cross_file.dart';

/// Builds an Image widget from XFile for mobile (io). Uses Image.file for immediate display.
/// Uses medium filter quality and cacheWidth to limit GPU memory on low-RAM kiosks.
Widget imageFromXFile(XFile file) {
  // Without cacheWidth the full capture (e.g. 1920×1080 = 8 MB RGBA) is
  // decoded even when displayed at ~400 logical pixels. Use a Builder to
  // read devicePixelRatio and clamp decode size.
  return Builder(
    builder: (context) {
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final screenWidth = MediaQuery.sizeOf(context).width;
      // Decode at screen width (not card width — we don't know it here)
      final cw = (screenWidth * dpr).ceil();
      return Image.file(
        File(file.path),
        fit: BoxFit.contain,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        cacheWidth: cw,
      );
    },
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
  return Builder(
    builder: (context) {
      final dpr = MediaQuery.devicePixelRatioOf(context);
      // Decode at display card size, not source image size.
      final cw = (width * dpr).ceil();
      final ch = (height * dpr).ceil();
      return Image.file(
        File(file.path),
        width: width,
        height: height,
        fit: fit,
        alignment: alignment,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        cacheWidth: cw,
        cacheHeight: ch,
      );
    },
  );
}
