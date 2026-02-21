import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:camera/camera.dart';
import '../services/file_helper.dart';

/// Standard format/size for all captured photos (any camera, any platform).
/// Ensures one common format and dimensions regardless of Flutter vs custom plugin.
const int kCapturedPhotoMaxDimension = 1920;
const int kCapturedPhotoJpegQuality = 85;

/// Metadata returned for a photo (dimensions, format label, and file size in bytes).
typedef ImageMetadata = ({int width, int height, String format, int fileSizeBytes});

/// Helper class for image processing operations
class ImageHelper {
  /// Returns width, height, format label, and file size for the given image file.
  /// Format is derived from file extension (e.g. JPEG, PNG).
  static Future<ImageMetadata?> getImageMetadata(XFile imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      if (bytes.isEmpty) return null;
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      final ext = imageFile.path.toLowerCase().split('.').last;
      final format = _formatLabelFromExtension(ext);
      return (
        width: decoded.width,
        height: decoded.height,
        format: format,
        fileSizeBytes: bytes.length,
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

  static String _formatLabelFromExtension(String ext) {
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

  /// Normalizes a captured photo to standard format and size, saves to app storage, and returns the new file.
  /// Used only when the standard Flutter camera plugin is used (custom plugin normalizes at native level).
  /// Standard: JPEG, max [kCapturedPhotoMaxDimension] px, [kCapturedPhotoJpegQuality]% quality.
  /// Heavy work (decode/resize/encode) runs in a background isolate to keep UI responsive.
  static Future<XFile> normalizeAndSaveCapturedPhoto(XFile sourceFile) async {
    final bytes = await sourceFile.readAsBytes();
    if (bytes.isEmpty) {
      throw Exception('Captured image is empty');
    }
    final normalizedBytes = await compute(
      _normalizeToStandardJpegBytes,
      bytes,
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
  static Uint8List _normalizeToStandardJpegBytes(Uint8List bytes) {
    final originalImage = img.decodeImage(bytes);
    if (originalImage == null) {
      throw Exception('Failed to decode captured image');
    }
    int targetWidth = originalImage.width;
    int targetHeight = originalImage.height;
    if (targetWidth > kCapturedPhotoMaxDimension || targetHeight > kCapturedPhotoMaxDimension) {
      final scale = (targetWidth > targetHeight)
          ? kCapturedPhotoMaxDimension / targetWidth
          : kCapturedPhotoMaxDimension / targetHeight;
      targetWidth = (targetWidth * scale).round();
      targetHeight = (targetHeight * scale).round();
    }
    final resized = img.copyResize(
      originalImage,
      width: targetWidth,
      height: targetHeight,
      interpolation: img.Interpolation.linear,
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
  static Future<String> resizeAndEncodeImage(
    XFile imageFile, {
    int maxWidth = 1920,
    int maxHeight = 1920,
    int minWidth = 512,
    int minHeight = 512,
    int quality = 85, // JPEG quality (0-100)
    int maxSizeBytes = 4 * 1024 * 1024, // 4MB (for 1920px at good quality)
  }) async {
    try {
      // Read image bytes
      final bytes = await imageFile.readAsBytes();
      if (bytes.isEmpty) {
        throw Exception('Image file is empty');
      }

      // Decode image
      final originalImage = img.decodeImage(bytes);
      if (originalImage == null) {
        throw Exception('Failed to decode image');
      }

      // Calculate target dimensions while maintaining aspect ratio
      int targetWidth = originalImage.width;
      int targetHeight = originalImage.height;

      // Scale down if too large
      if (targetWidth > maxWidth || targetHeight > maxHeight) {
        final scale = (targetWidth > targetHeight)
            ? maxWidth / targetWidth
            : maxHeight / targetHeight;
        targetWidth = (targetWidth * scale).round();
        targetHeight = (targetHeight * scale).round();
      }

      // Scale up if too small (but maintain aspect ratio)
      if (targetWidth < minWidth || targetHeight < minHeight) {
        final scale = (targetWidth < targetHeight)
            ? minWidth / targetWidth
            : minHeight / targetHeight;
        targetWidth = (targetWidth * scale).round();
        targetHeight = (targetHeight * scale).round();
      }

      // Resize image
      final resizedImage = img.copyResize(
        originalImage,
        width: targetWidth,
        height: targetHeight,
        interpolation: img.Interpolation.linear,
      );

      // Encode to JPEG with compression
      int currentQuality = quality;
      Uint8List? encodedBytes;

      // Try to compress to meet size requirements
      while (currentQuality >= 50) {
        encodedBytes = Uint8List.fromList(
          img.encodeJpg(resizedImage, quality: currentQuality),
        );

        // Check if size is acceptable
        if (encodedBytes.length <= maxSizeBytes) {
          break;
        }

        // Reduce quality and try again
        currentQuality -= 10;
      }

      // If still too large, resize further
      if (encodedBytes != null && encodedBytes.length > maxSizeBytes) {
        final additionalScale = (maxSizeBytes / encodedBytes.length) * 0.9; // 90% to be safe
        final newWidth = (targetWidth * additionalScale).round();
        final newHeight = (targetHeight * additionalScale).round();
        
        final furtherResized = img.copyResize(
          resizedImage,
          width: newWidth,
          height: newHeight,
          interpolation: img.Interpolation.linear,
        );
        
        encodedBytes = Uint8List.fromList(
          img.encodeJpg(furtherResized, quality: 75),
        );
      }

      if (encodedBytes == null || encodedBytes.isEmpty) {
        throw Exception('Failed to encode image');
      }

      // Convert to base64
      final base64String = base64Encode(encodedBytes);

      // Return data URL
      return 'data:image/jpeg;base64,$base64String';
    } catch (e) {
      throw Exception('Failed to resize and encode image: $e');
    }
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

  /// Rotates an image 180 degrees and overwrites the original file
  /// Returns a new XFile pointing to the rotated image
  static Future<XFile> rotateImage180(XFile imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      if (bytes.isEmpty) {
        throw Exception('Image file is empty');
      }

      final originalImage = img.decodeImage(bytes);
      if (originalImage == null) {
        throw Exception('Failed to decode image');
      }

      final rotatedImage = img.copyRotate(originalImage, angle: 180);
      final extension = imageFile.path.toLowerCase().split('.').last;

      Uint8List encodedBytes;
      if (extension == 'png') {
        encodedBytes = Uint8List.fromList(img.encodePng(rotatedImage));
      } else {
        encodedBytes = Uint8List.fromList(img.encodeJpg(rotatedImage, quality: 95));
      }

      final file = FileHelper.createFile(imageFile.path);
      await (file as dynamic).writeAsBytes(encodedBytes);

      return XFile((file as dynamic).path);
    } catch (e) {
      throw Exception('Failed to rotate image: $e');
    }
  }
}

