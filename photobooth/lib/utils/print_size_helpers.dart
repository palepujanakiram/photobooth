import '../screens/photo_generate/photo_generate_viewmodel.dart';
import 'constants.dart';
import 'print_orientation.dart';

/// True when [printSize] is the Classic dual-strip cutter token.
bool isStripDualPrintSize(String? printSize) {
  final size = printSize?.trim() ?? '';
  return size == AppConstants.kPrintSizeStripDual2x6;
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

/// Staff fallback: strip composite URL → dual 6×2; everything else → 4×6.
String resolveStaffNetworkPrintSize({
  required String imageUrl,
  String? stripCompositeUrl,
}) {
  if (_urlsReferToSameImage(imageUrl, stripCompositeUrl)) {
    return AppConstants.kPrintSizeStripDual2x6;
  }
  return AppConstants.kPrintSizePortrait4x6;
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
