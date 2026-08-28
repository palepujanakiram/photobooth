import 'package:flutter/painting.dart';

import 'constants.dart';

/// Decode target for [Image.network] / [Image.file] / [Image.memory]
/// `cacheWidth` / `cacheHeight` (Flutter's equivalent of Coil/Glide downsampling).
///
/// Only one dimension is set when inferred from layout so JPEG aspect is kept.
class NetworkImageDecodeSize {
  const NetworkImageDecodeSize({this.cacheWidth, this.cacheHeight});

  final int? cacheWidth;
  final int? cacheHeight;

  bool get hasDecodeTarget => cacheWidth != null || cacheHeight != null;
}

/// Layout + widget + explicit decode hints for [resolveNetworkImageDecodeSize].
class NetworkImageDecodeInput {
  const NetworkImageDecodeInput({
    required this.devicePixelRatio,
    this.layoutWidth,
    this.layoutHeight,
    this.widgetWidth,
    this.widgetHeight,
    this.explicitCacheWidth,
    this.explicitCacheHeight,
  });

  final double devicePixelRatio;
  final double? layoutWidth;
  final double? layoutHeight;
  final double? widgetWidth;
  final double? widgetHeight;
  final int? explicitCacheWidth;
  final int? explicitCacheHeight;
}

/// Clamp a decode pixel length. Non-finite values use [minPx].
int clampNetworkImageDecodePx(
  num px, {
  int minPx = 64,
  int maxPx = 2048,
}) {
  if (px.isNaN || px.isInfinite) return minPx;
  final rounded = px.round();
  if (rounded < minPx) return minPx;
  if (rounded > maxPx) return maxPx;
  return rounded;
}

/// Same as [resolveNetworkImageDecodeSize] using [AppConstants] decode caps.
///
/// When [downsample] is false and the caller did not set an explicit cache
/// size, returns no decode target (full-resolution) so pinch-zoom viewers
/// keep a sharp bitmap.
NetworkImageDecodeSize resolveAppNetworkImageDecodeSize(
  NetworkImageDecodeInput input, {
  bool downsample = true,
}) {
  if (!downsample &&
      input.explicitCacheWidth == null &&
      input.explicitCacheHeight == null) {
    return const NetworkImageDecodeSize();
  }
  return resolveNetworkImageDecodeSize(
    input,
    minDecodePx: AppConstants.kNetworkImageMinDecodePx,
    maxDecodePx: AppConstants.kNetworkImageMaxDecodePx,
  );
}

/// Picks a decode size so full-resolution network bitmaps are never allocated
/// for an on-screen widget. Caller [explicitCacheWidth]/[explicitCacheHeight]
/// always win.
NetworkImageDecodeSize resolveNetworkImageDecodeSize(
  NetworkImageDecodeInput input, {
  int minDecodePx = 64,
  int maxDecodePx = 2048,
}) {
  final explicitW = input.explicitCacheWidth;
  final explicitH = input.explicitCacheHeight;
  if (explicitW != null || explicitH != null) {
    return NetworkImageDecodeSize(
      cacheWidth: explicitW,
      cacheHeight: explicitH,
    );
  }
  return _decodeSizeFromLogical(
    _finitePositive(input.widgetWidth) ?? _finitePositive(input.layoutWidth),
    _finitePositive(input.widgetHeight) ?? _finitePositive(input.layoutHeight),
    _safeDevicePixelRatio(input.devicePixelRatio),
    minDecodePx,
    maxDecodePx,
  );
}

/// Wraps [provider] with [ResizeImage] when [decode] has a target.
ImageProvider resizeImageProviderIfNeeded(
  ImageProvider provider,
  NetworkImageDecodeSize decode,
) {
  return ResizeImage.resizeIfNeeded(
    decode.cacheWidth,
    decode.cacheHeight,
    provider,
  );
}

double _safeDevicePixelRatio(double dpr) {
  if (dpr.isNaN || dpr.isInfinite || dpr <= 0) return 1;
  return dpr;
}

double? _finitePositive(double? value) {
  if (value == null) return null;
  if (value.isNaN || value.isInfinite || value <= 0) return null;
  return value;
}

NetworkImageDecodeSize _decodeSizeFromLogical(
  double? logicalW,
  double? logicalH,
  double dpr,
  int minDecodePx,
  int maxDecodePx,
) {
  int px(double logical) => clampNetworkImageDecodePx(
        logical * dpr,
        minPx: minDecodePx,
        maxPx: maxDecodePx,
      );
  if (logicalW != null && logicalH != null) {
    return logicalW >= logicalH
        ? NetworkImageDecodeSize(cacheWidth: px(logicalW))
        : NetworkImageDecodeSize(cacheHeight: px(logicalH));
  }
  if (logicalW != null) {
    return NetworkImageDecodeSize(cacheWidth: px(logicalW));
  }
  if (logicalH != null) {
    return NetworkImageDecodeSize(cacheHeight: px(logicalH));
  }
  return NetworkImageDecodeSize(cacheWidth: maxDecodePx);
}
