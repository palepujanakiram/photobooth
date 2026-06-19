import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'session_user_image_validation.dart';

/// Long edge cap for session PATCH user image (mirrors [ImageHelper]).
const int kSessionPatchUserImageMaxLongEdgePx = 1536;
const int kSessionPatchUserImageJpegQuality = 85;

/// Smaller cap on web so encode + JSON PATCH stay responsive on the main thread.
const int kSessionPatchUserImageWebMaxLongEdgePx = 768;

Future<void> yieldToUiForImageEncode() => Future<void>.delayed(Duration.zero);

/// Session PATCH JPEG data URL under size cap (Sonar S3776 extraction).
String encodeSessionPatchUserImageUrl(
  Uint8List bytes, {
  int maxLongEdgePx = kSessionPatchUserImageMaxLongEdgePx,
}) {
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
