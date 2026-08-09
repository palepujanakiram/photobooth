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
