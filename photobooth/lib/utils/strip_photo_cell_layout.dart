import 'dart:ui';

import '../models/strip_models.dart';
import '../screens/fotoflashback/fotoflashback_strip_chrome_view_widgets.dart';

/// One photo slot on a 2×6 strip (absolute px in strip space).
class StripPhotoCellRect {
  const StripPhotoCellRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;

  Rect get rect => Rect.fromLTWH(left, top, width, height);
}

/// Whether POSE/print uses [BoxFit.contain] (filmstrip) vs cover (classic/noir).
bool stripPhotoCellUsesContainFit(String frameId) => frameId == 'filmstrip';

/// Letterbox well behind contain-fit cells (matches print chrome fill).
Color stripPhotoCellLetterboxColor(String frameId) {
  if (frameId == 'filmstrip') return const Color(0xFF0A0A0A);
  if (frameId == 'noir') return const Color(0xFF121216);
  return const Color(0xFFFFFFFF);
}

/// Photo cell geometry for one 2×6 strip — mirrors zenai `stripCompositor`.
///
/// Classic / Noir: 4px border, gutter 0 → four 592×448 cover cells on 600×1800.
/// Filmstrip: 52px rails, 72px top/bottom margin, 14px gutters, contain fit.
List<StripPhotoCellRect> computeStripPhotoCellRects({
  required String frameId,
  required double stripWidth,
  required double stripHeight,
  StripWysiwygLayout layout = StripWysiwygLayout.defaults,
}) {
  if (frameId == 'filmstrip') {
    return _filmstripCells(stripWidth, stripHeight, layout);
  }
  return _classicStripCells(stripWidth, stripHeight, layout);
}

List<StripPhotoCellRect> _classicStripCells(
  double stripWidth,
  double stripHeight,
  StripWysiwygLayout layout,
) {
  final border = stripWidth * layout.borderRatio;
  final cellW = stripWidth - 2 * border;
  final cellH = (stripHeight - 2 * border) / kStripShotCount;
  return [
    for (var i = 0; i < kStripShotCount; i++)
      StripPhotoCellRect(
        left: border,
        top: border + i * cellH,
        width: cellW,
        height: cellH,
      ),
  ];
}

List<StripPhotoCellRect> _filmstripCells(
  double stripWidth,
  double stripHeight,
  StripWysiwygLayout layout,
) {
  final rail = stripWidth * StripChromeLook.filmRailRatio;
  final marginY = stripHeight * layout.filmMarginY;
  final gutter = stripHeight * layout.filmGutter;
  final cellW = stripWidth - 2 * rail;
  final contentH = stripHeight - 2 * marginY;
  final cellH =
      (contentH - (kStripShotCount - 1) * gutter) / kStripShotCount;
  return [
    for (var i = 0; i < kStripShotCount; i++)
      StripPhotoCellRect(
        left: rail,
        top: marginY + i * (cellH + gutter),
        width: cellW,
        height: cellH,
      ),
  ];
}

/// Chrome overlay inset (rails for filmstrip, thin border otherwise).
double stripChromeBorderPad({
  required String frameId,
  required double stripWidth,
  StripWysiwygLayout layout = StripWysiwygLayout.defaults,
}) {
  if (frameId == 'filmstrip') {
    return stripWidth * StripChromeLook.filmRailRatio;
  }
  return stripWidth * layout.borderRatio;
}
