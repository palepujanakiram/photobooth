import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:camera/camera.dart';
import '../services/file_helper.dart';
import 'session_user_image_validation.dart';
import 'web_flow_trace.dart';

/// Standard format/size for all captured photos (any camera, any platform).
/// Ensures one common format and dimensions regardless of Flutter vs custom plugin.
const int kCapturedPhotoMaxDimension = 1920;
const int kCapturedPhotoJpegQuality = 85;

/// `PATCH /api/sessions/:id` `userImageUrl`: long edge cap and quality (API contract).
const int kSessionPatchUserImageMaxLongEdgePx = 1536;
const int kSessionPatchUserImageJpegQuality = 85;

/// Metadata returned for a photo (dimensions, format label, and file size in bytes).
typedef ImageMetadata = ({int width, int height, String format, int fileSizeBytes});

typedef _ImageMetadataIsolateArgs = ({Uint8List bytes, String path});

/// Isolate: decode, orient, scale to ≤ [kSessionPatchUserImageMaxLongEdgePx] on long edge,
/// JPEG [kSessionPatchUserImageJpegQuality], ensure data URL ≤ [SessionUserImageValidation.maxDataUrlCharacterLength].
String _encodeSessionPatchUserImageUrlIsolate(Uint8List bytes) {
  final original = img.decodeImage(bytes);
  if (original == null) {
    throw Exception('Failed to decode image for session upload');
  }
  var work = img.bakeOrientation(original);
  const cap = kSessionPatchUserImageMaxLongEdgePx;
  int w = work.width;
  int h = work.height;
  if (w > cap || h > cap) {
    final scale = (w > h) ? cap / w : cap / h;
    w = (w * scale).round();
    h = (h * scale).round();
  }
  work = img.copyResize(
    work,
    width: w,
    height: h,
    interpolation: img.Interpolation.cubic,
  );

  var quality = kSessionPatchUserImageJpegQuality;
  const maxChars = SessionUserImageValidation.maxDataUrlCharacterLength;

  while (true) {
    final enc = Uint8List.fromList(img.encodeJpg(work, quality: quality));
    final url = 'data:image/jpeg;base64,${base64Encode(enc)}';
    if (url.length <= maxChars) {
      return url;
    }
    quality -= 10;
    if (quality >= 55) {
      continue;
    }
    w = (w * 0.88).round().clamp(320, w);
    h = (h * 0.88).round().clamp(320, h);
    work = img.copyResize(
      work,
      width: w,
      height: h,
      interpolation: img.Interpolation.cubic,
    );
    quality = kSessionPatchUserImageJpegQuality;
    if (w <= 360 && h <= 360) {
      final enc2 = Uint8List.fromList(img.encodeJpg(work, quality: 65));
      final url2 = 'data:image/jpeg;base64,${base64Encode(enc2)}';
      if (url2.length > maxChars) {
        throw Exception('Could not compress image under upload size limit');
      }
      return url2;
    }
  }
}

String _extensionFormatLabel(String ext) {
  switch (ext) {
    case 'jpg':
    case 'jpeg':
      return 'JPEG';
    case 'png':
      return 'PNG';
    case 'gif':
      return 'GIF';
    case 'webp':
      return 'WebP';
    case 'heic':
      return 'HEIC';
    default:
      return ext.toUpperCase();
  }
}

/// Top-level for [compute] — must not reference [ImageHelper] instance state.
ImageMetadata? _decodeImageMetadataIsolate(_ImageMetadataIsolateArgs args) {
  final decoded = img.decodeImage(args.bytes);
  if (decoded == null) return null;
  final ext = args.path.toLowerCase().split('.').last;
  return (
    width: decoded.width,
    height: decoded.height,
    format: _extensionFormatLabel(ext),
    fileSizeBytes: args.bytes.length,
  );
}

/// Helper class for image processing operations
class ImageHelper {
  /// Returns width, height, format label, and file size for the given image file.
  /// Format is derived from file extension (e.g. JPEG, PNG).
  /// Decode runs in a background isolate so large photos do not block the UI.
  static Future<ImageMetadata?> getImageMetadata(XFile imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      if (bytes.isEmpty) return null;
      final path = imageFile.path;
      return compute(
        _decodeImageMetadataIsolate,
        (bytes: bytes, path: path),
      );
    } catch (_) {
      return null;
    }
  }

  /// Formats [bytes] as "X KB" or "X.X MB".
  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(mb >= 10 ? 0 : 1)} MB';
  }

  /// Normalizes a captured photo to standard format and size, saves to app storage, and returns the new file.
  /// Used only when the standard Flutter camera plugin is used (custom plugin normalizes at native level).
  /// Standard: JPEG, max [kCapturedPhotoMaxDimension] px, [kCapturedPhotoJpegQuality]% quality.
  /// Heavy work (decode/resize/encode) runs in a background isolate to keep UI responsive.
  static Future<XFile> normalizeAndSaveCapturedPhoto(
    XFile sourceFile, {
    bool flipHorizontal = false,
  }) async {
    // Web can't write to a temp directory. For web, just return the picked file as-is.
    // Upload resizing happens later in [resizeAndEncodeImage] (bytes-only), which is web-safe.
    if (kIsWeb) {
      return sourceFile;
    }
    final bytes = await sourceFile.readAsBytes();
    if (bytes.isEmpty) {
      throw Exception('Captured image is empty');
    }
    final normalizedBytes = await compute(
      _normalizeToStandardJpegBytes,
      (bytes: bytes, flipHorizontal: flipHorizontal),
    );
    final tempDir = await FileHelper.getTempDirectoryPath();
    const photosSubdir = 'photos';
    final photosDir = '$tempDir/$photosSubdir';
    await FileHelper.ensureDirectory(photosDir);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final savePath = '$photosDir/photo_$timestamp.jpg';
    final file = FileHelper.createFile(savePath);
    await (file as dynamic).writeAsBytes(normalizedBytes);
    return XFile((file as dynamic).path);
  }

  /// Top-level/static for compute(): decode, resize to standard max, encode JPEG. No file I/O.
  static Uint8List _normalizeToStandardJpegBytes(
    ({Uint8List bytes, bool flipHorizontal}) args,
  ) {
    final originalImage = img.decodeImage(args.bytes);
    if (originalImage == null) {
      throw Exception('Failed to decode captured image');
    }
    // Apply EXIF orientation so saved photos are upright everywhere.
    var normalized = img.bakeOrientation(originalImage);
    if (args.flipHorizontal) {
      normalized = img.flipHorizontal(normalized);
    }
    int targetWidth = normalized.width;
    int targetHeight = normalized.height;
    if (targetWidth > kCapturedPhotoMaxDimension || targetHeight > kCapturedPhotoMaxDimension) {
      final scale = (targetWidth > targetHeight)
          ? kCapturedPhotoMaxDimension / targetWidth
          : kCapturedPhotoMaxDimension / targetHeight;
      targetWidth = (targetWidth * scale).round();
      targetHeight = (targetHeight * scale).round();
    }
    final resized = img.copyResize(
      normalized,
      width: targetWidth,
      height: targetHeight,
      interpolation: img.Interpolation.cubic,
    );
    return Uint8List.fromList(
      img.encodeJpg(resized, quality: kCapturedPhotoJpegQuality),
    );
  }

  /// Resizes and compresses an image for upload (same max size as native save for display).
  ///
  /// Uses 1920px max to match native scale-at-save: one size for both display and upload.
  /// - Size: 512x512 to 1920x1920 pixels (maintains aspect ratio)
  /// - Max size: ~4MB after encoding (allows 1920px at good quality)
  /// - Format: JPEG
  ///
  /// Returns base64 encoded data URL: data:image/jpeg;base64,...
  ///
  /// All heavy work (decode, resize, encode, base64) runs in a background
  /// isolate via [compute] so it never blocks the UI thread or inflates
  /// main-isolate heap (important on 4 GB kiosks where an extra 20–40 MB
  /// of transient image buffers can push the process into OOM).
  static Future<String> resizeAndEncodeImage(
    XFile imageFile, {
    int maxWidth = 1920,
    int maxHeight = 1920,
    int minWidth = 512,
    int minHeight = 512,
    int quality = 85,
    int maxSizeBytes = 4 * 1024 * 1024,
  }) async {
    final bytes = await imageFile.readAsBytes();
    if (bytes.isEmpty) {
      throw Exception('Image file is empty');
    }
    return compute(
      _resizeAndEncodeIsolate,
      (
        bytes: bytes,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        minWidth: minWidth,
        minHeight: minHeight,
        quality: quality,
        maxSizeBytes: maxSizeBytes,
      ),
    );
  }

  /// Top-level for [compute] — must not reference instance state.
  static String _resizeAndEncodeIsolate(
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

    int targetWidth = originalImage.width;
    int targetHeight = originalImage.height;

    if (targetWidth > args.maxWidth || targetHeight > args.maxHeight) {
      final scale = (targetWidth > targetHeight)
          ? args.maxWidth / targetWidth
          : args.maxHeight / targetHeight;
      targetWidth = (targetWidth * scale).round();
      targetHeight = (targetHeight * scale).round();
    }

    if (targetWidth < args.minWidth || targetHeight < args.minHeight) {
      final scale = (targetWidth < targetHeight)
          ? args.minWidth / targetWidth
          : args.minHeight / targetHeight;
      targetWidth = (targetWidth * scale).round();
      targetHeight = (targetHeight * scale).round();
    }

    final resizedImage = img.copyResize(
      originalImage,
      width: targetWidth,
      height: targetHeight,
      interpolation: img.Interpolation.cubic,
    );

    int currentQuality = args.quality;
    Uint8List? encodedBytes;

    while (currentQuality >= 50) {
      encodedBytes = Uint8List.fromList(
        img.encodeJpg(resizedImage, quality: currentQuality),
      );
      if (encodedBytes.length <= args.maxSizeBytes) break;
      currentQuality -= 10;
    }

    if (encodedBytes != null && encodedBytes.length > args.maxSizeBytes) {
      final additionalScale =
          (args.maxSizeBytes / encodedBytes.length) * 0.9;
      final newWidth = (targetWidth * additionalScale).round();
      final newHeight = (targetHeight * additionalScale).round();
      final furtherResized = img.copyResize(
        resizedImage,
        width: newWidth,
        height: newHeight,
        interpolation: img.Interpolation.cubic,
      );
      encodedBytes = Uint8List.fromList(
        img.encodeJpg(furtherResized, quality: 75),
      );
    }

    if (encodedBytes == null || encodedBytes.isEmpty) {
      throw Exception('Failed to encode image');
    }

    final base64String = base64Encode(encodedBytes);
    return 'data:image/jpeg;base64,$base64String';
  }

  /// Encodes the capture for `PATCH /api/sessions/:id` field **`userImageUrl`**.
  ///
  /// Contract: **`data:image/jpeg;base64,...`** only, long edge ≤ **1536** px,
  /// JPEG quality **85**, size checked against [SessionUserImageValidation] after encode.
  /// Heavy work runs in a [compute] isolate (web + native).
  static Future<String> encodeImageForUpload(XFile imageFile) async {
    WebFlowTrace.log('ENCODE_IMPL', 'readAsBytes_start');
    final bytes = await imageFile.readAsBytes();
    WebFlowTrace.log('ENCODE_IMPL', 'readAsBytes_done len=${bytes.length}');
    if (bytes.isEmpty) {
      throw Exception('Image file is empty');
    }

    if (kIsWeb) {
      await Future<void>.delayed(Duration.zero);
      WebFlowTrace.log('ENCODE_IMPL', 'post_read_yield_done');
    }

    WebFlowTrace.log('ENCODE_IMPL', 'branch session_patch_encode longEdge=$kSessionPatchUserImageMaxLongEdgePx');
    final out = await compute(_encodeSessionPatchUserImageUrlIsolate, bytes);
    WebFlowTrace.log('ENCODE_IMPL', 'session_patch_encode_done outLen=${out.length}');
    SessionUserImageValidation.assertValidForSessionPatch(out);
    return out;
  }

  /// Converts image file to base64 data URL without resizing
  /// Use this if you want to preserve original image quality
  static Future<String> encodeImageToBase64(XFile imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      if (bytes.isEmpty) {
        throw Exception('Image file is empty');
      }

      final base64String = base64Encode(bytes);
      final extension = imageFile.path.toLowerCase().split('.').last;
      final mimeType = extension == 'png' ? 'image/png' : 'image/jpeg';

      return 'data:$mimeType;base64,$base64String';
    } catch (e) {
      throw Exception('Failed to encode image to base64: $e');
    }
  }

  /// Rotates an image 180 degrees and overwrites the original file.
  /// Heavy work runs in a background isolate to avoid main-thread heap spikes.
  /// Returns a new XFile pointing to the rotated image.
  static Future<XFile> rotateImage180(XFile imageFile) async {
    final bytes = await imageFile.readAsBytes();
    if (bytes.isEmpty) {
      throw Exception('Image file is empty');
    }
    final ext = imageFile.path.toLowerCase().split('.').last;
    final encodedBytes = await compute(
      _rotateImage180Isolate,
      (bytes: bytes, extension: ext),
    );
    final file = FileHelper.createFile(imageFile.path);
    await (file as dynamic).writeAsBytes(encodedBytes);
    return XFile((file as dynamic).path);
  }

  /// Top-level for [compute].
  static Uint8List _rotateImage180Isolate(
    ({Uint8List bytes, String extension}) args,
  ) {
    final originalImage = img.decodeImage(args.bytes);
    if (originalImage == null) {
      throw Exception('Failed to decode image');
    }
    final rotated = img.copyRotate(originalImage, angle: 180);
    if (args.extension == 'png') {
      return Uint8List.fromList(img.encodePng(rotated));
    }
    return Uint8List.fromList(img.encodeJpg(rotated, quality: 95));
  }
}

