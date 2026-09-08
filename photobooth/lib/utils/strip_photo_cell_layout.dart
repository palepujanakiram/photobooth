import 'package:flutter/painting.dart';

import '../models/strip_models.dart';
import '../screens/fotoflashback/fotoflashback_strip_chrome_view_widgets.dart';
import 'jpeg_sof_peek.dart';

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

/// Whether a strip cell letterboxes the capture instead of filling the window.
///
/// Classic / Noir / Filmstrip 1-shot contain-fits in the chrome window.
/// Occasion overlays (DPS) and multi-shot cells cover-fill the designed hole
/// so the photo stays large — no black letterbox inside the frame.
bool stripPhotoCellUsesContainFit(
  String frameId, {
  int shotCount = kStripShotCount,
}) {
  if (shotCount != 1) return false;
  if (isOccasionFrameId(frameId) || isStripTemplateFrame(frameId)) {
    return false;
  }
  return true;
}

/// Letterbox well behind contain-fit cells (matches print chrome fill).
Color stripPhotoCellLetterboxColor(String frameId) {
  if (isOccasionFrameId(frameId) || isStripTemplateFrame(frameId)) {
    return const Color(0xFF121212);
  }
  if (frameId == 'filmstrip') return const Color(0xFF0A0A0A);
  if (frameId == 'noir') return const Color(0xFF121216);
  return const Color(0xFFFFFFFF);
}

/// Whether cover-fill should keep the top of the capture (heads).
///
/// Only a **portrait** still in a **landscape** well uses top gravity. A
/// landscape webcam in a wide 3-shot / 4-shot hole stays centered — top-crop
/// would keep the ceiling and drop the subject off the bottom.
bool coverCropKeepsSourceTop({
  required double windowWidth,
  required double windowHeight,
  double? sourceWidth,
  double? sourceHeight,
}) {
  if (windowWidth <= windowHeight) return false;
  final sw = sourceWidth ?? 0;
  final sh = sourceHeight ?? 0;
  return sh > sw;
}

/// Cover-crop anchor for a photo well.
///
/// Portrait stills in a landscape well keep heads. Landscape stills, square
/// stills, and unknown source size stay centered.
Alignment coverPhotoAlignmentForWindow(
  double width,
  double height, {
  double? sourceWidth,
  double? sourceHeight,
}) =>
    coverCropKeepsSourceTop(
      windowWidth: width,
      windowHeight: height,
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
    )
        ? Alignment.topCenter
        : Alignment.center;

/// [coverPhotoAlignmentForWindow] using JPEG SOF size when bytes are present.
Alignment coverPhotoAlignmentForJpeg({
  required double windowWidth,
  required double windowHeight,
  List<int>? jpegBytes,
}) {
  final sof = jpegBytes == null || jpegBytes.isEmpty
      ? null
      : peekJpegSofDimensions(jpegBytes);
  return coverPhotoAlignmentForWindow(
    windowWidth,
    windowHeight,
    sourceWidth: sof?.width.toDouble(),
    sourceHeight: sof?.height.toDouble(),
  );
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
