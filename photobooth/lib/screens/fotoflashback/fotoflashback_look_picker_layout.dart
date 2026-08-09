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

/// Decode width for [Image.memory] on the look-picker strip / 6×4 preview.
///
/// Uses device pixel ratio so tablet/TV strips stay sharp; clamps so we do not
/// decode full Canon plates into GPU memory for a small on-screen cell.
int flashbackLookPreviewCacheWidth({
  required double layoutWidth,
  required double devicePixelRatio,
}) {
  if (!layoutWidth.isFinite || layoutWidth <= 0) return 1600;
  final dpr = devicePixelRatio.isFinite && devicePixelRatio > 0
      ? devicePixelRatio
      : 2.0;
  // Slight oversample (1.25×) so cover-crop + chrome still look crisp.
  final target = (layoutWidth * dpr * 1.25).round();
  return math.max(960, math.min(2400, target));
}
