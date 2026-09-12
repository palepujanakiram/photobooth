import 'dart:ui' show Size;

import '../screens/photo_generate/photo_generate_viewmodel.dart';
import 'constants.dart';
import 'print_orientation.dart';

/// Width ÷ height for Classic / AI thumbs on the print-selection hub.
///
/// Must match the deliverable so [BoxFit.contain] shows the full print the
/// guest finalized (cover + a fixed 0.72 tile was cropping heads off 4×6).
double printSelectionThumbAspectRatio(String? printSize) {
  final size = printSize?.trim().toLowerCase() ?? '';
  if (size == AppConstants.kPrintSizeLandscape6x4) {
    return 6 / 4;
  }
  if (size == AppConstants.kPrintSizePortrait4x6) {
    return 4 / 6;
  }
  if (size == AppConstants.kPrintSizeStripDual2x6) {
    // Dual 2×6 sheet is a 4×6 page.
    return 4 / 6;
  }
  return 4 / 6;
}

/// Caption row under the print thumb on [PrintSelectionScreen].
const double kPrintSelectionCaptionBand = 42;

/// Tile size that keeps a single print (image + caption) fully on screen.
Size fitPrintSelectionTile({
  required double maxWidth,
  required double maxHeight,
  required double printAspectWidthOverHeight,
  double captionBand = kPrintSelectionCaptionBand,
}) {
  final maxW = maxWidth.isFinite && maxWidth > 0 ? maxWidth : 0.0;
  final maxH = maxHeight.isFinite && maxHeight > 0 ? maxHeight : 0.0;
  if (maxW <= 0 || maxH <= 0) return Size.zero;
  final aspect = printAspectWidthOverHeight > 0
      ? printAspectWidthOverHeight
      : 4 / 6;
  final band = captionBand < 0 ? 0.0 : captionBand;
  var imageH = maxH - band;
  if (imageH < 1) imageH = maxH;
  var imageW = imageH * aspect;
  if (imageW > maxW) {
    imageW = maxW;
    imageH = imageW / aspect;
  }
  final tileH = imageH + band;
  if (tileH <= maxH) return Size(imageW, tileH);
  return Size(imageW, maxH);
}

/// True when [printSize] is the Classic dual-strip cutter token.
bool isStripDualPrintSize(String? printSize) {
  final size = printSize?.trim() ?? '';
  return size == AppConstants.kPrintSizeStripDual2x6;
}

/// Classic 3-shot and 4-shot print as two 2×6 strips (4×6 media + 2-inch cutter).
bool classicComposeUsesDualStripCutter(int? shotCount) =>
    shotCount == 3 || shotCount == 4;

/// Portrait 4×6 vs landscape 6×4 — customer orientation can override these.
bool isOrientationSelectablePrintSize(String? printSize) {
  final token = printSize?.trim().toLowerCase() ?? '';
  return token.isEmpty ||
      token == AppConstants.kPrintSizePortrait4x6 ||
      token == AppConstants.kPrintSizeLandscape6x4;
}

/// Resolves WCM print token after Classic strip compose.
///
/// One-shot uses [orientation] (`s6x4` / `s4x6`; default landscape) — never
/// the 2-inch cutter. 3-shot and 4-shot are always dual 2×6 (`s6x2_2`).
String resolveClassicComposePrintSize({
  required int imageCount,
  String? apiPrintSize,
  PrintOrientation? orientation,
}) {
  if (imageCount == 1) {
    return (orientation ?? PrintOrientation.landscape).printSize;
  }
  final fromApi = apiPrintSize?.trim() ?? '';
  if (isStripDualPrintSize(fromApi)) return fromApi;
  return AppConstants.kPrintSizeStripDual2x6;
}

/// Network printer `printSize` for one cart image.
///
/// Strip / cutter tokens on the image are fixed. AI defaults (`s4x6`) and empty
/// sizes follow [orientation] so BEHOLD portrait/landscape toggles reach DNP.
/// Never fall back to the session strip override (`s6x2_2`) for AI pages —
/// that caused mixed Classic+AI carts to send AI pages as dual-strip cuts.
String resolveNetworkPrintSizeForImage({
  required String? imagePrintSize,
  required PrintOrientation orientation,
  String? sessionOverride,
  int? classicComposeShotCount,
}) {
  if (classicComposeShotCount == 1) {
    return _oneShotNetworkPrintSize(
      imagePrintSize: imagePrintSize,
      orientation: orientation,
    );
  }

  final own = imagePrintSize?.trim() ?? '';
  if (own.isNotEmpty && !isOrientationSelectablePrintSize(own)) {
    return own;
  }

  final session = sessionOverride?.trim() ?? '';
  if (isStripDualPrintSize(session)) {
    return orientation.printSize;
  }
  if (session == AppConstants.kPrintSizeLandscape6x4) {
    return AppConstants.kPrintSizeLandscape6x4;
  }
  if (session.isNotEmpty && !isOrientationSelectablePrintSize(session)) {
    return session;
  }
  return orientation.printSize;
}

String _oneShotNetworkPrintSize({
  required String? imagePrintSize,
  required PrintOrientation orientation,
}) {
  final own = imagePrintSize?.trim() ?? '';
  if (own == AppConstants.kPrintSizeLandscape6x4 ||
      own == AppConstants.kPrintSizePortrait4x6) {
    return own;
  }
  return orientation.printSize;
}

/// Checkout session hint — Classic 1-shot is never dual-strip cutter.
String? resolveClassicCheckoutSessionPrintSize({
  required List<GeneratedImage> selected,
  String? stripPrintSize,
  int? classicComposeShotCount,
  required PrintOrientation orientation,
}) {
  if (classicComposeShotCount == 1) {
    return orientation.printSize;
  }
  if (selected.isEmpty) return null;
  final sizes = selected
      .map((e) => e.printSize?.trim() ?? '')
      .where((s) => s.isNotEmpty)
      .toSet();
  if (sizes.length == 1) return sizes.single;
  if (sizes.contains(AppConstants.kPrintSizeLandscape6x4) &&
      !sizes.contains(AppConstants.kPrintSizeStripDual2x6)) {
    return AppConstants.kPrintSizeLandscape6x4;
  }
  final hint = stripPrintSize?.trim() ?? '';
  return hint.isNotEmpty ? hint : null;
}

/// Cart token after Classic compose when the image omitted [printSize].
String resolveFlashbackCartPrintSize({
  required String? imagePrintSize,
  String? fallbackPrintSize,
  int? classicComposeShotCount,
  PrintOrientation orientation = PrintOrientation.portrait,
}) {
  if (classicComposeShotCount == 1) {
    return resolveClassicComposePrintSize(
      imageCount: 1,
      apiPrintSize: imagePrintSize ?? fallbackPrintSize,
      orientation: orientation,
    );
  }
  if (classicComposeUsesDualStripCutter(classicComposeShotCount)) {
    return AppConstants.kPrintSizeStripDual2x6;
  }
  final own = imagePrintSize?.trim() ?? '';
  if (own.isNotEmpty) return own;
  final fallback = fallbackPrintSize?.trim() ?? '';
  if (fallback.isNotEmpty) return fallback;
  return AppConstants.kPrintSizeStripDual2x6;
}

/// Fills missing [GeneratedImage.printSize] before pay/print (AI → orientation).
///
/// Classic strip images already carry `s6x2_2` from compose; this only backfills
/// theme / Explore more outputs that omitted the field.
List<GeneratedImage> ensureGeneratedImagePrintSizes(
  List<GeneratedImage> images, {
  PrintOrientation orientation = PrintOrientation.portrait,
}) {
  final fallback = orientation.printSize;
  return [
    for (final image in images)
      () {
        final own = image.printSize?.trim() ?? '';
        if (own.isNotEmpty && !isOrientationSelectablePrintSize(own)) {
          return image;
        }
        return image.copyWith(printSize: fallback);
      }(),
  ];
}

/// Compare deliverable URLs ignoring query (e.g. sessionId) and trailing slash.
bool imageUrlsReferToSameDeliverable(String? a, String? b) =>
    _urlsReferToSameImage(a, b);

/// Staff / reprint: infer WCM token from deliverable URLs and session hints.
///
/// 1-shot Classic and AI pages are never the dual-strip cutter — even when
/// the session catalog default (`s6x2_2`) was copied onto the deliverable.
/// 3-shot / 4-shot strip JPEGs stay `s6x2_2`. JPEG aspect in
/// [resolveStaffDnpPrintSize] then picks 4×6 vs 6×4 for uncut pages.
String resolveStaffNetworkPrintSize({
  required String imageUrl,
  String? stripCompositeUrl,
  String? single6x4Url,
  String? sessionPrintSize,
  int? classicComposeShotCount,
}) {
  if (classicComposeShotCount == 1) {
    return _staffOneShotPrintSize(
      imageUrl: imageUrl,
      single6x4Url: single6x4Url,
      sessionPrintSize: sessionPrintSize,
    );
  }

  final explicit = _normalizeStaffPrintSizeToken(sessionPrintSize);
  final isStripUrl = _urlsReferToSameImage(imageUrl, stripCompositeUrl);

  if (explicit == AppConstants.kPrintSizeLandscape6x4) {
    return AppConstants.kPrintSizeLandscape6x4;
  }
  if (explicit == AppConstants.kPrintSizePortrait4x6) {
    return AppConstants.kPrintSizePortrait4x6;
  }

  if (isStripUrl) {
    return AppConstants.kPrintSizeStripDual2x6;
  }

  final stripUrlMissing = stripCompositeUrl?.trim().isEmpty ?? true;
  if (isStripDualPrintSize(explicit) &&
      classicComposeUsesDualStripCutter(classicComposeShotCount) &&
      stripUrlMissing) {
    return AppConstants.kPrintSizeStripDual2x6;
  }

  if (isStripDualPrintSize(explicit)) {
    return AppConstants.kPrintSizePortrait4x6;
  }

  if (_urlsReferToSameImage(imageUrl, single6x4Url)) {
    return AppConstants.kPrintSizeLandscape6x4;
  }

  if (explicit != null) return explicit;

  return AppConstants.kPrintSizePortrait4x6;
}

String _staffOneShotPrintSize({
  required String imageUrl,
  String? single6x4Url,
  String? sessionPrintSize,
}) {
  final explicit = _normalizeStaffPrintSizeToken(sessionPrintSize);
  if (explicit == AppConstants.kPrintSizeLandscape6x4) {
    return AppConstants.kPrintSizeLandscape6x4;
  }
  if (explicit == AppConstants.kPrintSizePortrait4x6) {
    return AppConstants.kPrintSizePortrait4x6;
  }
  if (_urlsReferToSameImage(imageUrl, single6x4Url)) {
    return AppConstants.kPrintSizeLandscape6x4;
  }
  return AppConstants.kPrintSizePortrait4x6;
}

String? _normalizeStaffPrintSizeToken(String? raw) {
  final trimmed = raw?.trim() ?? '';
  if (trimmed.isEmpty) return null;
  switch (trimmed.toLowerCase()) {
    case 's4x6':
      return AppConstants.kPrintSizePortrait4x6;
    case 's6x4':
      return AppConstants.kPrintSizeLandscape6x4;
    case 's6x2_2':
      return AppConstants.kPrintSizeStripDual2x6;
    default:
      return trimmed;
  }
}

/// Compare deliverable URLs ignoring query (e.g. sessionId) and trailing slash.
bool _urlsReferToSameImage(String? a, String? b) {
  final left = _urlIdentity(a);
  final right = _urlIdentity(b);
  if (left.isEmpty || right.isEmpty) return false;
  return left == right;
}

String _urlIdentity(String? raw) {
  final trimmed = raw?.trim() ?? '';
  if (trimmed.isEmpty) return '';
  final withoutQuery = trimmed.split('?').first.split('#').first;
  if (withoutQuery.length > 1 && withoutQuery.endsWith('/')) {
    return withoutQuery.substring(0, withoutQuery.length - 1);
  }
  return withoutQuery;
}
