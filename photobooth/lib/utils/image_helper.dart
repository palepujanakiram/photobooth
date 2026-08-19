import 'dart:async';
import 'dart:convert';
import 'dart:io' show File;
import 'dart:ui' as ui;

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

/// FotoFlashback strip stills — booth print quality without multi‑MP transfer lag.
///
/// 1920 long-edge is enough for 4×6 / dual 2×6; 3840 forced ~8MB Canon JPEGs
/// through Pi sharp + Flutter bake and made 4-shot gaps feel stuck (~30s+).
const int kStripCapturedPhotoMaxDimension = 1920;
const int kStripCapturedPhotoJpegQuality = 92;

/// DNP / Selphy photo print encode — match booth still quality (avoid a second
/// soft 85% pass after a sharp 1920 px sidecar capture).
const int kDnpPrintJpegQuality = kStripCapturedPhotoJpegQuality;

/// `PATCH /api/sessions/:id` `userImageUrl`: long edge cap and quality (API contract).
const int kSessionPatchUserImageMaxLongEdgePx = 1536;
const int kSessionPatchUserImageJpegQuality = 85;

/// Reads JPEG SOF width/height without decoding the bitmap.
({int width, int height})? peekJpegSofDimensions(List<int> bytes) {
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
    return null;
  }
  var i = 2;
  while (i + 1 < bytes.length) {
    if (bytes[i] != 0xFF) {
      i++;
      continue;
    }
    final marker = bytes[i + 1];
    if (marker == 0xD8 ||
        marker == 0xD9 ||
        marker == 0x01 ||
        (marker >= 0xD0 && marker <= 0xD7)) {
      i += 2;
      continue;
    }
    if (i + 3 >= bytes.length) return null;
    final len = (bytes[i + 2] << 8) | bytes[i + 3];
    if (len < 2) return null;
    final isSof = marker == 0xC0 ||
        marker == 0xC1 ||
        marker == 0xC2 ||
        marker == 0xC3;
    if (isSof) {
      if (i + 8 >= bytes.length) return null;
      final height = (bytes[i + 5] << 8) | bytes[i + 6];
      final width = (bytes[i + 7] << 8) | bytes[i + 8];
      if (width > 0 && height > 0) {
        return (width: width, height: height);
      }
      return null;
    }
    i += 2 + len;
  }
  return null;
}

/// Average luma 0–255 from a tiny Skia decode. Used to detect underexposed
/// Canon stills vs the gain-boosted live-view JPEG.
Future<double?> meanJpegLuma(Uint8List bytes, {int sampleWidth = 48}) async {
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
    return null;
  }
  if (sampleWidth <= 0) return null;
  try {
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: sampleWidth,
    );
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final bd = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (bd == null) return null;
      final px = bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes);
      var sum = 0;
      var n = 0;
      for (var i = 0; i + 3 < px.length; i += 4) {
        sum += (px[i] * 3 + px[i + 1] * 6 + px[i + 2]) ~/ 10;
        n++;
      }
      if (n == 0) return null;
      return sum / n;
    } finally {
      image.dispose();
      codec.dispose();
    }
  } catch (_) {
    return null;
  }
}

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

  /// Bake still pixels so look/print match the upright live HDMI/UVC preview.
  ///
  /// When [quarterTurns] is 0: EXIF-only bake via Skia (no extra rotate).
  /// When non-zero: Skia decode then rotate — negative = CCW / left
  /// (FOTO lock **-1** = 90° towards the left).
  static Future<XFile> bakeExifAndQuarterTurns(
    XFile sourceFile, {
    int quarterTurns = 0,
    int jpegQuality = kCapturedPhotoJpegQuality,
  }) async {
    if (kIsWeb) return sourceFile;
    // Preserve sign: -1 = 90° CCW (left). Only |turns|%4==0 means "no rotate".
    final turnsMod = ((quarterTurns % 4) + 4) % 4;
    final quality = jpegQuality.clamp(1, 100);
    if (turnsMod == 0) {
      return _bakeExifOrientationOnly(sourceFile, jpegQuality: quality);
    }
    final path = sourceFile.path;
    final bytes = path.isNotEmpty
        ? await File(path).readAsBytes()
        : await sourceFile.readAsBytes();
    if (bytes.isEmpty) {
      throw Exception('Captured image is empty');
    }
    try {
      // Pass signed turns (-1 → angle -90) so "left" is not mapped to +270 CW.
      final bakedBytes = await _bakeSkiaQuarterTurns(
        bytes,
        quarterTurns: quarterTurns,
        jpegQuality: quality,
      );
      return _writeBakedJpegBytes(bakedBytes);
    } catch (_) {
      final bakedBytes = await compute(
        _bakeExifAndQuarterTurnsBytes,
        (
          bytes: bytes,
          quarterTurns: quarterTurns,
          jpegQuality: quality,
        ),
      );
      return _writeBakedJpegBytes(bakedBytes);
    }
  }

  /// Decode with [ui.instantiateImageCodec] target size so 20MP Canon stills
  /// never allocate a full-resolution RGBA buffer on 4GB kiosks.
  static Future<XFile> downscaleJpegToMaxLongEdge(
    XFile sourceFile, {
    int maxLongEdge = kCapturedPhotoMaxDimension,
    int jpegQuality = 95,
  }) async {
    if (kIsWeb) return sourceFile;
    final path = sourceFile.path;
    final bytes = path.isNotEmpty
        ? await File(path).readAsBytes()
        : await sourceFile.readAsBytes();
    if (bytes.isEmpty) {
      throw Exception('Captured image is empty');
    }
    final size = peekJpegSofDimensions(bytes);
    if (size == null ||
        (size.width <= maxLongEdge && size.height <= maxLongEdge)) {
      return sourceFile;
    }
    final quality = jpegQuality.clamp(1, 100);
    final landscape = size.width >= size.height;
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: landscape ? maxLongEdge : null,
      targetHeight: landscape ? null : maxLongEdge,
    );
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final bd = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (bd == null) {
        throw Exception('Skia downscale produced empty pixels');
      }
      final rgba = bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes);
      final bakedBytes = await compute(
        _encodeRgbaToJpegIsolate,
        (
          rgba: rgba,
          width: image.width,
          height: image.height,
          jpegQuality: quality,
          quarterTurns: 0,
        ),
      );
      return _writeBakedJpegBytes(bakedBytes);
    } finally {
      image.dispose();
      codec.dispose();
    }
  }

  /// Skia decode → signed quarter-turns (negative = CCW / left) → JPEG.
  static Future<Uint8List> _bakeSkiaQuarterTurns(
    Uint8List bytes, {
    required int quarterTurns,
    required int jpegQuality,
  }) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final bd = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (bd == null) {
        throw Exception('Skia bake produced empty pixels');
      }
      final rgba = bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes);
      return compute(
        _encodeRgbaToJpegIsolate,
        (
          rgba: rgba,
          width: image.width,
          height: image.height,
          jpegQuality: jpegQuality,
          quarterTurns: quarterTurns,
        ),
      );
    } finally {
      image.dispose();
    }
  }

  /// EXIF Orientation → pixels when live bake turns are locked to 0.
  ///
  /// Uses Skia ([ui.instantiateImageCodec]) to decode — Dart `image` JPEG
  /// decode corrupts many Canon/gphoto stills into green static that then gets
  /// trusted as `/photos/photo_*.jpg` and uploaded as the YOU image.
  static Future<XFile> _bakeExifOrientationOnly(
    XFile sourceFile, {
    required int jpegQuality,
  }) async {
    final path = sourceFile.path;
    final bytes = path.isNotEmpty
        ? await File(path).readAsBytes()
        : await sourceFile.readAsBytes();
    if (bytes.isEmpty) {
      throw Exception('Captured image is empty');
    }
    // Already upright for tag-less consumers — keep original Canon bytes.
    if (_peekJpegExifOrientation(bytes) <= 1) {
      return sourceFile;
    }
    try {
      final bakedBytes = await _bakeExifOrientationWithSkia(
        bytes,
        jpegQuality: jpegQuality,
      );
      return _writeBakedJpegBytes(bakedBytes);
    } catch (_) {
      // Prefer original bytes over dart-image re-encode (green static).
      return sourceFile;
    }
  }

  static Future<Uint8List> _bakeExifOrientationWithSkia(
    Uint8List bytes, {
    required int jpegQuality,
  }) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final bd = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (bd == null) {
        throw Exception('Skia EXIF bake produced empty pixels');
      }
      final rgba = bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes);
      return compute(
        _encodeRgbaToJpegIsolate,
        (
          rgba: rgba,
          width: image.width,
          height: image.height,
          jpegQuality: jpegQuality,
          quarterTurns: 0,
        ),
      );
    } finally {
      image.dispose();
    }
  }

  /// Top-level for [compute]: RGBA (Skia) → optional CW turns → JPEG.
  static Uint8List _encodeRgbaToJpegIsolate(
    ({
      Uint8List rgba,
      int width,
      int height,
      int jpegQuality,
      int quarterTurns,
    }) args,
  ) {
    var image = img.Image.fromBytes(
      width: args.width,
      height: args.height,
      bytes: args.rgba.buffer,
      bytesOffset: args.rgba.offsetInBytes,
      rowStride: args.width * 4,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );
    // Negative quarterTurns = CCW (e.g. -1 → -90° = 90° left).
    if (args.quarterTurns != 0) {
      image = img.copyRotate(image, angle: args.quarterTurns * 90);
    }
    return Uint8List.fromList(
      img.encodeJpg(image, quality: args.jpegQuality),
    );
  }

  static Future<XFile> _writeBakedJpegBytes(Uint8List bakedBytes) async {
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

  /// Top-level for [compute]: sensor pixels → live-feed quarter-turns (fallback).
  static Uint8List _bakeExifAndQuarterTurnsBytes(_BakeExifTurnsArgs args) {
    var work = _decodeJpegSensorPixels(args.bytes);
    if (args.quarterTurns != 0) {
      work = img.copyRotate(work, angle: args.quarterTurns * 90);
    }
    return Uint8List.fromList(
      img.encodeJpg(work, quality: args.jpegQuality),
    );
  }

  /// EXIF orientation tag without applying it (1 when absent / unreadable).
  static int _peekJpegExifOrientation(Uint8List bytes) {
    try {
      final jpeg = img.JpegData()..read(bytes);
      if (jpeg.exif.imageIfd.hasOrientation) {
        return jpeg.exif.imageIfd.orientation ?? 1;
      }
    } catch (_) {
      // Fall through.
    }
    return 1;
  }

  /// JPEG pixel buffer with EXIF orientation ignored (same space as HDMI frames).
  static img.Image _decodeJpegSensorPixels(Uint8List bytes) {
    try {
      final jpeg = img.JpegData()..read(bytes);
      if (jpeg.exif.imageIfd.hasOrientation) {
        jpeg.exif.imageIfd.orientation = null;
      }
      final image = jpeg.getImage();
      if (image.width > 0 && image.height > 0) return image;
    } catch (_) {
      // Fall through to generic decode.
    }
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw Exception('Failed to decode captured image');
    }
    return decoded;
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
    final turns = ((args.quarterTurns % 4) + 4) % 4;
    late img.Image normalized;
    if (turns != 0) {
      // Same rule as [bakeExifAndQuarterTurns]: rotate sensor pixels so UVC
      // stills match live [RotatedBox] (do not EXIF-bake then rotate again).
      normalized = _decodeJpegSensorPixels(args.bytes);
      normalized = img.copyRotate(normalized, angle: turns * 90);
    } else {
      final originalImage = img.decodeImage(args.bytes);
      if (originalImage == null) {
        throw Exception('Failed to decode captured image');
      }
      normalized = img.bakeOrientation(originalImage);
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

