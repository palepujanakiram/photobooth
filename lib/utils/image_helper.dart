import 'dart:typed_data';
import 'dart:convert';
import 'package:image/image.dart' as img;
import 'package:camera/camera.dart';

/// Helper class for image processing operations
class ImageHelper {
  /// Resizes and compresses an image to meet API requirements
  /// 
  /// Requirements:
  /// - Size: 512x512 to 1024x1024 pixels (maintains aspect ratio)
  /// - Max size: ~2MB after base64 encoding
  /// - Format: JPEG
  /// 
  /// Returns base64 encoded data URL: data:image/jpeg;base64,...
  static Future<String> resizeAndEncodeImage(
    XFile imageFile, {
    int maxWidth = 1024,
    int maxHeight = 1024,
    int minWidth = 512,
    int minHeight = 512,
    int quality = 85, // JPEG quality (0-100)
    int maxSizeBytes = 2 * 1024 * 1024, // 2MB
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
}

