import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../utils/constants.dart';

/// Phone look-picker content width (historical compose column).
const double kFlashbackLookPickerMaxWidthPhone = 760;

/// Tablet / kiosk look-picker content width — keeps print aspect, uses more
/// of an ~11" landscape canvas than the phone 760 cap.
const double kFlashbackLookPickerMaxWidthTablet = 1200;

/// Max width for the Classic "Pick your look" body column.
///
/// Phones stay at [kFlashbackLookPickerMaxWidthPhone]. Tablets/kiosks
/// ([shortestSide] ≥ [AppConstants.kTabletBreakpoint]) use
/// [kFlashbackLookPickerMaxWidthTablet] so the strip preview can grow without
/// changing 4×6 / strip geometry.
double flashbackLookPickerMaxContentWidth(double shortestSide) {
  if (shortestSide >= AppConstants.kTabletBreakpoint) {
    return kFlashbackLookPickerMaxWidthTablet;
  }
  return kFlashbackLookPickerMaxWidthPhone;
}

/// Min decode px for look-screen photos / overlays (small cells stay readable).
const int kFlashbackLookPreviewCacheWidthMin = 320;

/// Max decode px on the long edge. 4GB Android TV OOMs if look taps decode
/// print-size JPEG/PNG textures (old cap 1280 × 4 cells + overlay).
const int kFlashbackLookPreviewCacheWidthMax = 720;

/// Bilinear is sharp enough for kiosk preview; [FilterQuality.high] saveLayers
/// of 4-shot ColorFiltered strips freeze Amlogic TV on every look/frame tap.
const FilterQuality kFlashbackLookPreviewFilterQuality = FilterQuality.medium;

/// Decode width for [Image.memory] on the look-picker strip / 6×4 preview.
///
/// Pass the **cell** (or overlay) layout edge, not the full strip width, so
/// four photos are not each decoded at strip resolution.
int flashbackLookPreviewCacheWidth({
  required double layoutWidth,
  required double devicePixelRatio,
}) {
  if (!layoutWidth.isFinite || layoutWidth <= 0) {
    return kFlashbackLookPreviewCacheWidthMax;
  }
  final dpr = devicePixelRatio.isFinite && devicePixelRatio > 0
      ? devicePixelRatio
      : 2.0;
  // Slight oversample (1.25×) so cover-crop + chrome still look crisp.
  final target = (layoutWidth * dpr * 1.25).round();
  return math.max(
    kFlashbackLookPreviewCacheWidthMin,
    math.min(kFlashbackLookPreviewCacheWidthMax, target),
  );
}

/// Decode target for occasion overlay PNGs (tall strip vs landscape 6×4).
///
/// Only the long edge is set so aspect is kept and print-size alpha textures
/// are not uploaded when guests tap Classic frames.
({int? cacheWidth, int? cacheHeight}) flashbackLookOverlayDecodeSize({
  required double layoutWidth,
  required double layoutHeight,
  required double devicePixelRatio,
}) {
  final portrait = layoutHeight >= layoutWidth;
  final cap = flashbackLookPreviewCacheWidth(
    layoutWidth: portrait ? layoutHeight : layoutWidth,
    devicePixelRatio: devicePixelRatio,
  );
  if (portrait) {
    return (cacheWidth: null, cacheHeight: cap);
  }
  return (cacheWidth: cap, cacheHeight: null);
}
