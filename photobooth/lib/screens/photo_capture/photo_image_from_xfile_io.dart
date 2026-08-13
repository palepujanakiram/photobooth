import 'dart:io' show File;
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';

import '../../utils/app_strings.dart';

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
      return _stillImage(
        file: file,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        cacheWidth: cw,
      );
    },
  );
}

/// Same as [imageFromXFile] but with explicit width/height. [fit] defaults to [BoxFit.contain];
/// use [BoxFit.cover] when the photo aspect (e.g. landscape webcam) differs from a portrait card.
///
/// When [sharpDisplay] is true (post-capture review), decode the full still so review
/// is not softened by [cacheWidth] / [cacheHeight] downscaling.
Widget imageFromXFileSized(
  XFile file,
  double width,
  double height, {
  BoxFit fit = BoxFit.contain,
  Alignment alignment = Alignment.center,
  bool sharpDisplay = false,
}) {
  if (sharpDisplay) {
    return _stillImage(
      file: file,
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      filterQuality: FilterQuality.none,
    );
  }

  return Builder(
    builder: (context) {
      final dpr = MediaQuery.devicePixelRatioOf(context);
      // Decode at display card size, not source image size.
      // Only cacheWidth so Flutter preserves JPEG aspect (both dims can
      // produce a 0-height decode on some kiosk layouts).
      final cw = (width * dpr).ceil();
      return _stillImage(
        file: file,
        width: width,
        height: height,
        fit: fit,
        alignment: alignment,
        filterQuality: FilterQuality.medium,
        cacheWidth: cw > 0 ? cw : null,
      );
    },
  );
}

Widget _stillImage({
  required XFile file,
  double? width,
  double? height,
  BoxFit fit = BoxFit.contain,
  Alignment alignment = Alignment.center,
  FilterQuality filterQuality = FilterQuality.medium,
  int? cacheWidth,
}) {
  if (file.path.isEmpty) {
    return FutureBuilder<Uint8List>(
      future: file.readAsBytes(),
      builder: (context, snapshot) {
        if (snapshot.hasError ||
            (snapshot.hasData && snapshot.data!.isEmpty)) {
          return _stillDecodeError(width: width, height: height);
        }
        if (!snapshot.hasData) {
          return _stillLoading(width: width, height: height);
        }
        return Image.memory(
          snapshot.data!,
          width: width,
          height: height,
          fit: fit,
          alignment: alignment,
          gaplessPlayback: true,
          filterQuality: filterQuality,
          cacheWidth: cacheWidth,
          frameBuilder: _stillFrameBuilder(width: width, height: height),
          errorBuilder: (context, error, stackTrace) =>
              _stillDecodeError(width: width, height: height),
        );
      },
    );
  }

  return Image.file(
    File(file.path),
    width: width,
    height: height,
    fit: fit,
    alignment: alignment,
    gaplessPlayback: true,
    filterQuality: filterQuality,
    cacheWidth: cacheWidth,
    frameBuilder: _stillFrameBuilder(width: width, height: height),
    errorBuilder: (context, error, stackTrace) =>
        _stillDecodeError(width: width, height: height),
  );
}

ImageFrameBuilder _stillFrameBuilder({double? width, double? height}) {
  return (context, child, frame, wasSynchronouslyLoaded) {
    if (wasSynchronouslyLoaded || frame != null) return child;
    return _stillLoading(width: width, height: height);
  };
}

Widget _stillLoading({double? width, double? height}) {
  return SizedBox(
    width: width,
    height: height,
    child: const ColoredBox(
      color: Colors.black,
      child: Center(
        child: CircularProgressIndicator(color: Colors.white70),
      ),
    ),
  );
}

Widget _stillDecodeError({double? width, double? height}) {
  return SizedBox(
    width: width,
    height: height,
    child: const ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            AppStrings.captureStillDisplayFailed,
            style: TextStyle(color: Colors.white70),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    ),
  );
}
