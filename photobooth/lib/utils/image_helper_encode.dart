import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'jpeg_sof_peek.dart';
import 'session_user_image_validation.dart';

/// Long edge cap for session PATCH user image (mirrors [ImageHelper]).
const int kSessionPatchUserImageMaxLongEdgePx = 1536;
const int kSessionPatchUserImageJpegQuality = 85;

/// Kiosk captures (sidecar, PTP derivative, normalize) are capped at 1920 long edge.
const int kKioskCaptureTrustMaxLongEdgePx = 1920;

/// Guest media dir written by [persistCapturedGuestXFile] after shutter.
const String kFotozenMediaPathMarker = '/fotozen_media/';

/// Smaller cap on web so encode + JSON PATCH stay responsive on the main thread.
const int kSessionPatchUserImageWebMaxLongEdgePx = 768;

Future<void> yieldToUiForImageEncode() => Future<void>.delayed(Duration.zero);

/// Reuses already-normalized JPEG bytes when they fit session PATCH limits.
///
/// Capture-time [ImageHelper.normalizeAndSaveCapturedPhoto] often produces a
/// JPEG at ≤1024–1920 px; re-decoding and re-encoding on Continue doubles
/// isolate work and can hang low-RAM kiosks when USB teardown runs in parallel.
String? tryReuseNormalizedJpegForSessionPatch(Uint8List bytes) {
  if (bytes.length < 2 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
    return null;
  }
  if (bytes.length > SessionUserImageValidation.maxDecodedPayloadBytes) {
    return null;
  }
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final w = decoded.width;
  final h = decoded.height;
  if (w > kSessionPatchUserImageMaxLongEdgePx ||
      h > kSessionPatchUserImageMaxLongEdgePx) {
    return null;
  }
  final url = 'data:image/jpeg;base64,${base64Encode(bytes)}';
  if (url.length > SessionUserImageValidation.maxDataUrlCharacterLength) {
    return null;
  }
  return url;
}

/// Suffix written by the native `DisplayDerivative` for a direct-PTP capture.
///
/// Matched as a **suffix, not a directory**, on purpose: the direct-PTP capture
/// folder (`<files>/captures/<sessionId>/`) holds the untouched ~7 MB camera
/// original next to its derivative, and trusting the folder would hand a
/// 6000×4000 JPEG straight to the session PATCH. Only this suffix carries the
/// 1920/q90 guarantee.
const String kNativeDisplayDerivativeSuffix = '.display.jpg';

/// App temp capture from [ImageHelper.normalizeAndSaveCapturedPhoto], Pi
/// sidecar, or the native direct-PTP display derivative.
bool isAppNormalizedCapturePath(String path) {
  if (path.isEmpty) return false;
  final lower = path.toLowerCase();
  if (!lower.endsWith('.jpg') && !lower.endsWith('.jpeg')) return false;
  // Direct-PTP stills are bounded to 1920 long edge at q90 by `DisplayDerivative`
  // (Android BitmapFactory + Bitmap.compress, hardware-backed), written expressly
  // as the review/upload copy while the original never crosses into Dart.
  //
  // Missing from this predicate, direct PTP was the *only* source falling through
  // to the pure-Dart decode → cubic resize → JPEG re-encode. That runs inside the
  // 90s AppConstants.kSessionUploadTimeout wrapping _ensureUploadBase64Ready, and
  // on an Android TV box it blew through it — surfacing as "Upload took too long,
  // check your connection" on a healthy camera and a healthy network. EDSDK and Pi
  // never showed it because `/sidecar/` already short-circuits the same work.
  if (lower.endsWith(kNativeDisplayDerivativeSuffix)) return true;
  // Sidecar stills are already ~1920 JPEG from gphoto — never re-decode with
  // Dart `image` (corrupts Canon → green static on YOU / Gemini input).
  if (lower.contains('/photos/photo_') || lower.contains('/sidecar/')) {
    return true;
  }
  // [persistCapturedGuestXFile] copies normalized stills here before upload.
  // Without this, Continue falls through to Dart decode→resize on TV boxes.
  return lower.contains(kFotozenMediaPathMarker);
}

/// Trust capture-time normalize output — no decode/resize (kiosk Continue path).
///
/// Normalize already capped dimensions and fixed UVC color; re-encoding in a
/// second [compute] isolate was taking 10–20+ seconds on Android TV kiosks.
String? tryTrustNormalizedJpegBytesForSessionPatch(Uint8List bytes) {
  if (bytes.length < 2 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
    return null;
  }
  if (bytes.length > SessionUserImageValidation.maxDecodedPayloadBytes) {
    return null;
  }
  final sof = peekJpegSofDimensions(bytes);
  if (sof == null) return null;
  final longEdge =
      sof.width > sof.height ? sof.width : sof.height;
  if (longEdge > kKioskCaptureTrustMaxLongEdgePx) {
    return null;
  }
  final url = 'data:image/jpeg;base64,${base64Encode(bytes)}';
  if (url.length > SessionUserImageValidation.maxDataUrlCharacterLength) {
    return null;
  }
  return url;
}

/// Session PATCH JPEG data URL under size cap (Sonar S3776 extraction).
String encodeSessionPatchUserImageUrl(
  Uint8List bytes, {
  int maxLongEdgePx = kSessionPatchUserImageMaxLongEdgePx,
}) {
  final reused = tryReuseNormalizedJpegForSessionPatch(bytes);
  if (reused != null) return reused;

  final original = img.decodeImage(bytes);
  if (original == null) {
    throw Exception('Failed to decode image for session upload');
  }
  var work = img.bakeOrientation(original);
  work = _scaleSessionPatchImage(work, maxLongEdgePx: maxLongEdgePx);

  var quality = kSessionPatchUserImageJpegQuality;
  const maxChars = SessionUserImageValidation.maxDataUrlCharacterLength;

  while (true) {
    final url = _sessionPatchDataUrl(work, quality);
    if (url.length <= maxChars) return url;
    quality -= 10;
    if (quality >= 55) continue;
    work = _shrinkSessionPatchImage(work);
    quality = kSessionPatchUserImageJpegQuality;
    if (work.width <= 360 && work.height <= 360) {
      return _sessionPatchDataUrlOrThrow(work, 65, maxChars);
    }
  }
}

/// Web-safe encode: yields between heavy steps so the loader timer can repaint.
Future<String> encodeSessionPatchUserImageUrlAsync(
  Uint8List bytes, {
  int maxLongEdgePx = kSessionPatchUserImageWebMaxLongEdgePx,
}) async {
  await yieldToUiForImageEncode();
  final reused = tryReuseNormalizedJpegForSessionPatch(bytes);
  if (reused != null) return reused;
  final original = img.decodeImage(bytes);
  if (original == null) {
    throw Exception('Failed to decode image for session upload');
  }
  await yieldToUiForImageEncode();
  var work = img.bakeOrientation(original);
  await yieldToUiForImageEncode();
  work = _scaleSessionPatchImage(work, maxLongEdgePx: maxLongEdgePx);

  var quality = kSessionPatchUserImageJpegQuality;
  const maxChars = SessionUserImageValidation.maxDataUrlCharacterLength;

  while (true) {
    await yieldToUiForImageEncode();
    final url = _sessionPatchDataUrl(work, quality);
    if (url.length <= maxChars) return url;
    quality -= 10;
    if (quality >= 55) continue;
    await yieldToUiForImageEncode();
    work = _shrinkSessionPatchImage(work);
    quality = kSessionPatchUserImageJpegQuality;
    if (work.width <= 360 && work.height <= 360) {
      return _sessionPatchDataUrlOrThrow(work, 65, maxChars);
    }
  }
}

img.Image _scaleSessionPatchImage(
  img.Image work, {
  required int maxLongEdgePx,
}) {
  var w = work.width;
  var h = work.height;
  if (w <= maxLongEdgePx && h <= maxLongEdgePx) return work;
  final scale = (w > h) ? maxLongEdgePx / w : maxLongEdgePx / h;
  w = (w * scale).round();
  h = (h * scale).round();
  return img.copyResize(
    work,
    width: w,
    height: h,
    interpolation: img.Interpolation.cubic,
  );
}

img.Image _shrinkSessionPatchImage(img.Image work) {
  final w = (work.width * 0.88).round().clamp(320, work.width);
  final h = (work.height * 0.88).round().clamp(320, work.height);
  return img.copyResize(
    work,
    width: w,
    height: h,
    interpolation: img.Interpolation.cubic,
  );
}

String _sessionPatchDataUrl(img.Image work, int quality) {
  final enc = Uint8List.fromList(img.encodeJpg(work, quality: quality));
  return 'data:image/jpeg;base64,${base64Encode(enc)}';
}

String _sessionPatchDataUrlOrThrow(img.Image work, int quality, int maxChars) {
  final url = _sessionPatchDataUrl(work, quality);
  if (url.length > maxChars) {
    throw Exception('Could not compress image under upload size limit');
  }
  return url;
}

/// Resize + JPEG encode for upload (Sonar S3776 extraction; used from [compute]).
String resizeAndEncodeImageIsolate(
  ({
    Uint8List bytes,
    int maxWidth,
    int maxHeight,
    int minWidth,
    int minHeight,
    int quality,
    int maxSizeBytes,
  }) args,
) {
  final originalImage = img.decodeImage(args.bytes);
  if (originalImage == null) {
    throw Exception('Failed to decode image');
  }

  final dims = _computeUploadTargetDimensions(
    originalImage.width,
    originalImage.height,
    maxWidth: args.maxWidth,
    maxHeight: args.maxHeight,
    minWidth: args.minWidth,
    minHeight: args.minHeight,
  );

  final resizedImage = img.copyResize(
    originalImage,
    width: dims.$1,
    height: dims.$2,
    interpolation: img.Interpolation.cubic,
  );

  final encodedBytes = _encodeUploadJpegUnderMaxSize(
    resizedImage,
    targetWidth: dims.$1,
    targetHeight: dims.$2,
    quality: args.quality,
    maxSizeBytes: args.maxSizeBytes,
  );

  if (encodedBytes.isEmpty) {
    throw Exception('Failed to encode image');
  }

  return 'data:image/jpeg;base64,${base64Encode(encodedBytes)}';
}

(int, int) _computeUploadTargetDimensions(
  int width,
  int height, {
  required int maxWidth,
  required int maxHeight,
  required int minWidth,
  required int minHeight,
}) {
  var targetWidth = width;
  var targetHeight = height;

  if (targetWidth > maxWidth || targetHeight > maxHeight) {
    final scale = (targetWidth > targetHeight)
        ? maxWidth / targetWidth
        : maxHeight / targetHeight;
    targetWidth = (targetWidth * scale).round();
    targetHeight = (targetHeight * scale).round();
  }

  if (targetWidth < minWidth || targetHeight < minHeight) {
    final scale = (targetWidth < targetHeight)
        ? minWidth / targetWidth
        : minHeight / targetHeight;
    targetWidth = (targetWidth * scale).round();
    targetHeight = (targetHeight * scale).round();
  }

  return (targetWidth, targetHeight);
}

Uint8List _encodeUploadJpegUnderMaxSize(
  img.Image resizedImage, {
  required int targetWidth,
  required int targetHeight,
  required int quality,
  required int maxSizeBytes,
}) {
  var currentQuality = quality;
  Uint8List? encodedBytes;

  while (currentQuality >= 50) {
    encodedBytes = Uint8List.fromList(
      img.encodeJpg(resizedImage, quality: currentQuality),
    );
    if (encodedBytes.length <= maxSizeBytes) return encodedBytes;
    currentQuality -= 10;
  }

  if (encodedBytes != null && encodedBytes.length > maxSizeBytes) {
    final additionalScale = (maxSizeBytes / encodedBytes.length) * 0.9;
    final newWidth = (targetWidth * additionalScale).round();
    final newHeight = (targetHeight * additionalScale).round();
    final furtherResized = img.copyResize(
      resizedImage,
      width: newWidth,
      height: newHeight,
      interpolation: img.Interpolation.cubic,
    );
    return Uint8List.fromList(img.encodeJpg(furtherResized, quality: 75));
  }

  return encodedBytes ?? Uint8List(0);
}
