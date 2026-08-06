import 'dart:async';
import 'dart:convert';
import 'dart:io' show File;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:camera/camera.dart';
import '../services/file_helper.dart';
import 'image_helper_channel_fix.dart';
import 'image_helper_encode.dart';
import 'session_user_image_validation.dart';
import 'app_strings.dart';
import 'web_flow_trace.dart';

/// Standard format/size for all captured photos (any camera, any platform).
/// Ensures one common format and dimensions regardless of Flutter vs custom plugin.
const int kCapturedPhotoMaxDimension = 1920;
const int kCapturedPhotoJpegQuality = 85;

/// FotoFlashback strip stills — keep more source pixels + quality before compose.
const int kStripCapturedPhotoMaxDimension = 3840;
const int kStripCapturedPhotoJpegQuality = 97;

/// `PATCH /api/sessions/:id` `userImageUrl`: long edge cap and quality (API contract).
const int kSessionPatchUserImageMaxLongEdgePx = 1536;
const int kSessionPatchUserImageJpegQuality = 85;

/// Metadata returned for a photo (dimensions, format label, and file size in bytes).
typedef ImageMetadata = ({int width, int height, String format, int fileSizeBytes});

typedef _ImageMetadataIsolateArgs = ({Uint8List bytes, String path});

typedef _NormalizeJpegArgs = ({
  Uint8List bytes,
  bool flipHorizontal,
  bool fixBgrChannelOrder,
  int quarterTurns,
  int maxDimension,
  int jpegQuality,
});

typedef _NormalizeJpegPathArgs = ({
  String path,
  bool flipHorizontal,
  bool fixBgrChannelOrder,
  int quarterTurns,
  int maxDimension,
  int jpegQuality,
});

typedef _BakeExifTurnsArgs = ({
  Uint8List bytes,
  int quarterTurns,
  int jpegQuality,
});

typedef _BakeExifTurnsPathArgs = ({
  String path,
  int quarterTurns,
  int jpegQuality,
});

/// Isolate entry: session PATCH user image encoding.
String _encodeSessionPatchUserImageUrlIsolate(Uint8List bytes) {
  final reused = tryReuseNormalizedJpegForSessionPatch(bytes);
  if (reused != null) return reused;
  return encodeSessionPatchUserImageUrl(bytes);
}

/// Isolate entry: read normalized capture from disk, then encode for PATCH.
String _encodeSessionPatchUserImageUrlFromPathIsolate(String path) {
  final bytes = File(path).readAsBytesSync();
  if (bytes.isEmpty) {
    throw Exception(AppStrings.imageFileEmpty);
  }
  return _encodeSessionPatchUserImageUrlIsolate(bytes);
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

String _base64EncodeIsolate(Uint8List bytes) => base64Encode(bytes);

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
    /// Some Android UVC plugins save stills with R/B swapped (blue skin tones).
    bool fixBgrChannelOrder = false,
    /// Clockwise quarter-turns to match live [RotatedBox] preview (UVC/HDMI).
    int quarterTurns = 0,
    int? maxDimension,
    int? jpegQuality,
  }) async {
    // Web can't write to a temp directory. For web, just return the picked file as-is.
    // Upload resizing happens later in [resizeAndEncodeImage] (bytes-only), which is web-safe.
    if (kIsWeb) {
      return sourceFile;
    }
    final path = sourceFile.path;
    final turns = ((quarterTurns % 4) + 4) % 4;
    final normalizedBytes = path.isNotEmpty
        ? await compute(
            _normalizeToStandardJpegBytesFromPath,
            (
              path: path,
              flipHorizontal: flipHorizontal,
              fixBgrChannelOrder: fixBgrChannelOrder,
              quarterTurns: turns,
              maxDimension: maxDimension ?? kCapturedPhotoMaxDimension,
              jpegQuality: jpegQuality ?? kCapturedPhotoJpegQuality,
            ),
          )
        : await compute(
            _normalizeToStandardJpegBytes,
            (
              bytes: await sourceFile.readAsBytes(),
              flipHorizontal: flipHorizontal,
              fixBgrChannelOrder: fixBgrChannelOrder,
              quarterTurns: turns,
              maxDimension: maxDimension ?? kCapturedPhotoMaxDimension,
              jpegQuality: jpegQuality ?? kCapturedPhotoJpegQuality,
            ),
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

  /// Lightweight UVC fallback: downscale + BGR channel fix without full normalize.
  ///
  /// Used when full [normalizeAndSaveCapturedPhoto] times out or OOMs on kiosks.
  static Future<XFile> fixUvcBgrAndSave(
    XFile sourceFile, {
    int? maxDimension,
    int? jpegQuality,
  }) {
    return normalizeAndSaveCapturedPhoto(
      sourceFile,
      fixBgrChannelOrder: true,
      maxDimension: maxDimension,
      jpegQuality: jpegQuality,
    );
  }

  /// Copies a capture still into app temp storage without decode/re-encode.
  ///
  /// Used on memory-constrained kiosks where UVC [takePicture] already returns
  /// a JPEG at the negotiated preview resolution.
  static Future<XFile> copyCaptureToAppPhotosDir(XFile sourceFile) async {
    if (kIsWeb) return sourceFile;
    final path = sourceFile.path;
    if (path.isEmpty) {
      throw Exception('Captured image path is empty');
    }
    final source = File(path);
    if (!await source.exists()) {
      throw Exception('Captured image file missing: $path');
    }
    final tempDir = await FileHelper.getTempDirectoryPath();
    const photosSubdir = 'photos';
    final photosDir = '$tempDir/$photosSubdir';
    await FileHelper.ensureDirectory(photosDir);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final savePath = '$photosDir/photo_$timestamp.jpg';
    await source.copy(savePath);
    return XFile(savePath);
  }

  /// Bake EXIF orientation and optional clockwise quarter-turns into pixels.
  ///
  /// Used for Pi sidecar / HDMI kiosk stills that skip full normalize (too
  /// heavy on Android TV) but still need print/compose to match the upright
  /// live preview ([RotatedBox] quarter-turns are display-only otherwise).
  static Future<XFile> bakeExifAndQuarterTurns(
    XFile sourceFile, {
    int quarterTurns = 0,
    int jpegQuality = kCapturedPhotoJpegQuality,
  }) async {
    if (kIsWeb) return sourceFile;
    final turns = ((quarterTurns % 4) + 4) % 4;
    final quality = jpegQuality.clamp(1, 100);
    final path = sourceFile.path;
    final Uint8List bakedBytes = path.isNotEmpty
        ? await compute(
            _bakeExifAndQuarterTurnsFromPath,
            (
              path: path,
              quarterTurns: turns,
              jpegQuality: quality,
            ),
          )
        : await compute(
            _bakeExifAndQuarterTurnsBytes,
            (
              bytes: await sourceFile.readAsBytes(),
              quarterTurns: turns,
              jpegQuality: quality,
            ),
          );
    final tempDir = await FileHelper.getTempDirectoryPath();
    const photosSubdir = 'photos';
    final photosDir = '$tempDir/$photosSubdir';
    await FileHelper.ensureDirectory(photosDir);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final savePath = '$photosDir/photo_$timestamp.jpg';
    final file = FileHelper.createFile(savePath);
    await (file as dynamic).writeAsBytes(bakedBytes);
    return XFile((file as dynamic).path);
  }

  static Uint8List _bakeExifAndQuarterTurnsFromPath(
    _BakeExifTurnsPathArgs args,
  ) {
    final bytes = File(args.path).readAsBytesSync();
    if (bytes.isEmpty) {
      throw Exception('Captured image is empty');
    }
    return _bakeExifAndQuarterTurnsBytes((
      bytes: bytes,
      quarterTurns: args.quarterTurns,
      jpegQuality: args.jpegQuality,
    ));
  }

  /// Top-level for [compute]: EXIF bake + clockwise quarter-turns.
  static Uint8List _bakeExifAndQuarterTurnsBytes(_BakeExifTurnsArgs args) {
    final originalImage = img.decodeImage(args.bytes);
    if (originalImage == null) {
      throw Exception('Failed to decode captured image');
    }
    var work = img.bakeOrientation(originalImage);
    final turns = ((args.quarterTurns % 4) + 4) % 4;
    if (turns != 0) {
      work = img.copyRotate(work, angle: turns * 90);
    }
    return Uint8List.fromList(
      img.encodeJpg(work, quality: args.jpegQuality),
    );
  }

  /// Deletes a temp capture file after normalization to free disk/RAM on kiosks.
  static Future<void> tryDeleteLocalFile(String? path) async {
    if (kIsWeb || path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Best-effort.
    }
  }

  /// Top-level for [compute]: read path in isolate, then decode/resize/encode.
  static Uint8List _normalizeToStandardJpegBytesFromPath(
    _NormalizeJpegPathArgs args,
  ) {
    final bytes = File(args.path).readAsBytesSync();
    if (bytes.isEmpty) {
      throw Exception('Captured image is empty');
    }
    return _normalizeToStandardJpegBytes((
      bytes: bytes,
      flipHorizontal: args.flipHorizontal,
      fixBgrChannelOrder: args.fixBgrChannelOrder,
      quarterTurns: args.quarterTurns,
      maxDimension: args.maxDimension,
      jpegQuality: args.jpegQuality,
    ));
  }

  /// Top-level/static for compute(): decode, resize to standard max, encode JPEG. No file I/O.
  static Uint8List _normalizeToStandardJpegBytes(_NormalizeJpegArgs args) {
    final originalImage = img.decodeImage(args.bytes);
    if (originalImage == null) {
      throw Exception('Failed to decode captured image');
    }
    // Apply EXIF orientation so saved photos are upright everywhere.
    var normalized = img.bakeOrientation(originalImage);
    final turns = ((args.quarterTurns % 4) + 4) % 4;
    if (turns != 0) {
      normalized = img.copyRotate(normalized, angle: turns * 90);
    }
    final maxDim = args.maxDimension;

    // Downscale before channel fix / flip to cap peak RAM in the isolate (UVC
    // plugin saves full preview frames as JPEG quality 100).
    if (normalized.width > maxDim || normalized.height > maxDim) {
      final scale = (normalized.width > normalized.height)
          ? maxDim / normalized.width
          : maxDim / normalized.height;
      normalized = img.copyResize(
        normalized,
        width: (normalized.width * scale).round(),
        height: (normalized.height * scale).round(),
        // Cubic keeps more edge detail than linear for print-bound strip shots.
        interpolation: img.Interpolation.cubic,
      );
    }

    if (args.fixBgrChannelOrder) {
      normalized = swapRedAndBlueChannels(normalized);
    }
    if (args.flipHorizontal) {
      normalized = img.flipHorizontal(normalized);
    }

    return Uint8List.fromList(
      img.encodeJpg(
        normalized,
        quality: args.jpegQuality,
      ),
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
      throw Exception(AppStrings.imageFileEmpty);
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
  ) =>
      resizeAndEncodeImageIsolate(args);

  /// Encodes the capture for `PATCH /api/sessions/:id` field **`userImageUrl`**.
  ///
  /// Contract: **`data:image/jpeg;base64,...`** only, long edge ≤ **1536** px,
  /// JPEG quality **85**, size checked against [SessionUserImageValidation] after encode.
  /// Heavy work runs in a [compute] isolate (web + native).
  static Future<String> encodeImageForUpload(XFile imageFile) async {
    if (!kIsWeb) {
      final path = imageFile.path;
      if (path.isNotEmpty && await File(path).exists()) {
        if (isAppNormalizedCapturePath(path)) {
          WebFlowTrace.log('ENCODE_IMPL', 'branch trusted_normalized');
          final bytes = await File(path).readAsBytes().timeout(
            const Duration(seconds: 8),
            onTimeout: () => throw TimeoutException(
              'Reading normalized capture for upload timed out',
            ),
          );
          final trusted = tryTrustNormalizedJpegBytesForSessionPatch(bytes);
          if (trusted != null) {
            WebFlowTrace.log(
              'ENCODE_IMPL',
              'trusted_normalized_done outLen=${trusted.length}',
            );
            SessionUserImageValidation.assertValidForSessionPatch(trusted);
            return trusted;
          }
        }
        WebFlowTrace.log('ENCODE_IMPL', 'branch path_isolate');
        final out = await compute(
          _encodeSessionPatchUserImageUrlFromPathIsolate,
          path,
        ).timeout(
          const Duration(seconds: 20),
          onTimeout: () => throw TimeoutException(
            'Encoding photo for upload timed out',
          ),
        );
        WebFlowTrace.log('ENCODE_IMPL', 'path_isolate_done outLen=${out.length}');
        SessionUserImageValidation.assertValidForSessionPatch(out);
        return out;
      }
    }

    WebFlowTrace.log('ENCODE_IMPL', 'readAsBytes_start');
    final bytes = await imageFile.readAsBytes().timeout(
      const Duration(seconds: 20),
      onTimeout: () => throw TimeoutException(
        'Reading captured photo for upload timed out',
      ),
    );
    WebFlowTrace.log('ENCODE_IMPL', 'readAsBytes_done len=${bytes.length}');
    if (bytes.isEmpty) {
      throw Exception(AppStrings.imageFileEmpty);
    }

    if (kIsWeb) {
      await Future<void>.delayed(Duration.zero);
      WebFlowTrace.log('ENCODE_IMPL', 'post_read_yield_done');
    }

    if (kIsWeb) {
      final reused = tryReuseNormalizedJpegForSessionPatch(bytes);
      if (reused != null) {
        WebFlowTrace.log('ENCODE_IMPL', 'branch web_reuse_normalized len=${reused.length}');
        SessionUserImageValidation.assertValidForSessionPatch(reused);
        return reused;
      }
      WebFlowTrace.log(
        'ENCODE_IMPL',
        'branch web_async_encode longEdge=$kSessionPatchUserImageWebMaxLongEdgePx',
      );
      final out = await encodeSessionPatchUserImageUrlAsync(bytes);
      WebFlowTrace.log('ENCODE_IMPL', 'web_async_encode_done outLen=${out.length}');
      SessionUserImageValidation.assertValidForSessionPatch(out);
      return out;
    }

    WebFlowTrace.log('ENCODE_IMPL', 'branch session_patch_encode longEdge=$kSessionPatchUserImageMaxLongEdgePx');
    final out = await compute(_encodeSessionPatchUserImageUrlIsolate, bytes).timeout(
      const Duration(seconds: 45),
      onTimeout: () => throw TimeoutException(
        'Encoding photo for upload timed out',
      ),
    );
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
        throw Exception(AppStrings.imageFileEmpty);
      }

      // Large Classic stills — keep base64 off the UI isolate.
      final base64String = bytes.length > 256 * 1024
          ? await compute(_base64EncodeIsolate, bytes)
          : base64Encode(bytes);
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
      throw Exception(AppStrings.imageFileEmpty);
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

