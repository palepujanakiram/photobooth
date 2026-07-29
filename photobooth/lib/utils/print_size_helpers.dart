import '../screens/photo_generate/photo_generate_viewmodel.dart';
import 'constants.dart';
import 'print_orientation.dart';

/// True when [printSize] is the Classic dual-strip cutter token.
bool isStripDualPrintSize(String? printSize) {
  final size = printSize?.trim() ?? '';
  return size == AppConstants.kPrintSizeStripDual2x6;
}

/// Resolves WCM print token after Classic strip compose.
///
/// One-shot uses [orientation] (`s6x4` / `s4x6`; default landscape).
/// Four-shot landscape prefers `s6x4` (four-up); portrait uses API dual-strip /
/// sheet size (default portrait when [orientation] is omitted).
String resolveClassicComposePrintSize({
  required int imageCount,
  String? apiPrintSize,
  PrintOrientation? orientation,
}) {
  final resolved = orientation ??
      (imageCount == 1
          ? PrintOrientation.landscape
          : PrintOrientation.portrait);
  if (imageCount == 1) {
    return resolved.printSize;
  }
  if (resolved == PrintOrientation.landscape) {
    final fromApi = apiPrintSize?.trim() ?? '';
    if (fromApi == AppConstants.kPrintSizeLandscape6x4) {
      return fromApi;
    }
    return AppConstants.kPrintSizeLandscape6x4;
  }
  final fromApi = apiPrintSize?.trim() ?? '';
  if (fromApi.isNotEmpty) return fromApi;
  return AppConstants.kPrintSizeStripDual2x6;
}

/// Network printer `printSize` for one cart image.
///
/// Prefer the image's own [GeneratedImage.printSize]. Never fall back to the
/// session strip override (`s6x2_2`) for images that did not declare a size —
/// that caused mixed Classic+AI carts to send AI pages as dual-strip cuts.
String resolveNetworkPrintSizeForImage({
  required String? imagePrintSize,
  required PrintOrientation orientation,
  String? sessionOverride,
}) {
  final own = imagePrintSize?.trim() ?? '';
  if (own.isNotEmpty) return own;

  final session = sessionOverride?.trim() ?? '';
  if (session == AppConstants.kPrintSizeLandscape6x4) {
    return AppConstants.kPrintSizeLandscape6x4;
  }
  if (isStripDualPrintSize(session)) {
    return orientation.printSize;
  }
  if (session.isNotEmpty) return session;
  return orientation.printSize;
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
        if (own.isNotEmpty) return image;
        return image.copyWith(printSize: fallback);
      }(),
  ];
}

/// Compare deliverable URLs ignoring query (e.g. sessionId) and trailing slash.
bool imageUrlsReferToSameDeliverable(String? a, String? b) =>
    _urlsReferToSameImage(a, b);

/// Staff / reprint: infer WCM token from deliverable URLs and session hints.
///
/// When [sessionPrintSize] is set (from session or generatedImages), it wins.
/// URL equality with [stripCompositeUrl] alone must not force dual-strip cut for
/// Classic 1-shot sessions where the API reused the same URL for both fields.
String resolveStaffNetworkPrintSize({
  required String imageUrl,
  String? stripCompositeUrl,
  String? single6x4Url,
  String? sessionPrintSize,
  int? classicComposeShotCount,
}) {
  final explicit = _normalizeStaffPrintSizeToken(sessionPrintSize);
  if (explicit != null) return explicit;

  if (_urlsReferToSameImage(imageUrl, single6x4Url)) {
    return AppConstants.kPrintSizeLandscape6x4;
  }

  if (_urlsReferToSameImage(imageUrl, stripCompositeUrl)) {
    if (classicComposeShotCount == 1) {
      return AppConstants.kPrintSizeLandscape6x4;
    }
    return AppConstants.kPrintSizeStripDual2x6;
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
