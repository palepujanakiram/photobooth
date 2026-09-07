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

/// Whether POSE/print uses [BoxFit.contain] (legacy) vs cover (all chrome frames).
bool stripPhotoCellUsesContainFit(String frameId) => false;

/// Letterbox well behind contain-fit cells (matches print chrome fill).
Color stripPhotoCellLetterboxColor(String frameId) {
  if (frameId == 'filmstrip') return const Color(0xFF0A0A0A);
  if (frameId == 'noir') return const Color(0xFF121216);
  return const Color(0xFFFFFFFF);
}

/// Photo cell geometry for one 2×6 strip — mirrors zenai `stripCompositor`.
///
/// Classic / Noir (HAMA-style): 10px equal margins, 10px gutters.
/// Filmstrip: 36px rails, same vertical stack as classic, cover fit.
List<StripPhotoCellRect> computeStripPhotoCellRects({
  required String frameId,
  required double stripWidth,
  required double stripHeight,
  StripWysiwygLayout layout = StripWysiwygLayout.defaults,
  int shotCount = kStripShotCount,
  List<StripTemplateSlot>? templateSlots,
}) {
  final n = shotCount < 1 ? kStripShotCount : shotCount;
  if (templateSlots != null && templateSlots.length == n) {
    return [
      for (final slot in templateSlots)
        StripPhotoCellRect(
          left: slot.left * stripWidth,
          top: slot.top * stripHeight,
          width: slot.width * stripWidth,
          height: slot.height * stripHeight,
        ),
    ];
  }
  if (frameId == 'filmstrip') {
    return _filmstripCells(stripWidth, stripHeight, layout, n);
  }
  return _classicStripCells(stripWidth, stripHeight, layout, n);
}

/// Overlay PNG + slotted photos when the catalog has a 6×2 template.
List<StripTemplateSlot>? resolveStripPreviewTemplateSlots({
  required String frameId,
  required int shotCount,
  List<StripTemplateSlot> catalogSlots = const [],
  String? overlayUrl,
}) {
  final overlay = overlayUrl?.trim() ?? '';
  if (overlay.isEmpty || !isStripTemplateFrame(frameId)) return null;
  if (catalogSlots.length == shotCount) return catalogSlots;
  return defaultOccasionStripSlots(shotCount);
}

List<StripPhotoCellRect> _classicStripCells(
  double stripWidth,
  double stripHeight,
  StripWysiwygLayout layout,
  int shotCount,
) {
  final side = stripWidth * layout.borderRatio;
  final topPad = stripHeight * layout.borderTopRatio;
  final bottomPad = stripHeight * layout.borderBottomRatio;
  final gutter = stripHeight * layout.gutterRatio;
  final cellW = stripWidth - 2 * side;
  final cellH =
      (stripHeight - topPad - bottomPad - (shotCount - 1) * gutter) /
          shotCount;
  return [
    for (var i = 0; i < shotCount; i++)
      StripPhotoCellRect(
        left: side,
        top: topPad + i * (cellH + gutter),
        width: cellW,
        height: cellH,
      ),
  ];
}

List<StripPhotoCellRect> _filmstripCells(
  double stripWidth,
  double stripHeight,
  StripWysiwygLayout layout,
  int shotCount,
) {
  final rail = stripWidth * StripChromeLook.filmRailRatio;
  final marginY = stripHeight * layout.filmMarginY;
  final gutter = stripHeight * layout.filmGutter;
  final cellW = stripWidth - 2 * rail;
  final bottomPad = stripHeight * layout.borderBottomRatio;
  final contentH = stripHeight - marginY - bottomPad;
  final cellH =
      (contentH - (shotCount - 1) * gutter) / shotCount;
  return [
    for (var i = 0; i < shotCount; i++)
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
