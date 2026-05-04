import 'dart:ui';
import 'package:share_plus/share_plus.dart';
import '../utils/constants.dart';
import '../utils/exceptions.dart';

class ShareService {
  Future<void> shareText(
    String text, {
    Rect? sharePositionOrigin,
    String? subject,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw ShareException('Nothing to share');
    }
    try {
      final origin = sharePositionOrigin ?? _getDefaultSharePosition();
      await SharePlus.instance.share(
        ShareParams(
          text: trimmed,
          subject: subject ?? AppConstants.kBrandName,
          sharePositionOrigin: origin,
        ),
      );
    } catch (e) {
      throw ShareException('Failed to share: $e');
    }
  }

  /// Shares an image file via WhatsApp or other sharing options
  /// Works with XFile on all platforms (iOS, Android, Web)
  /// 
  /// For iOS: Pass [sharePositionOrigin] to position the share sheet properly
  Future<void> shareImage(
    XFile imageFile, {
    String? text,
    Rect? sharePositionOrigin,
  }) async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [imageFile],
          text: text,
          subject: '${AppConstants.kBrandName} image',
          sharePositionOrigin: sharePositionOrigin,
        ),
      );
    } catch (e) {
      throw ShareException('Failed to share image: $e');
    }
  }

  /// Shares an image specifically via WhatsApp
  /// Works with XFile on all platforms (iOS, Android, Web)
  /// 
  /// For iOS: Pass [sharePositionOrigin] to position the share sheet properly
  /// If not provided, will use a default center position
  Future<void> shareViaWhatsApp(
    XFile imageFile, {
    String? text,
    Rect? sharePositionOrigin,
  }) async {
    try {
      // If no position provided, use a default center position for iOS
      final origin = sharePositionOrigin ?? _getDefaultSharePosition();
      
      await SharePlus.instance.share(
        ShareParams(
          files: [imageFile],
          text: text ?? 'Check out my photo!',
          subject: '${AppConstants.kBrandName} image',
          sharePositionOrigin: origin,
        ),
      );
    } catch (e) {
      throw ShareException('Failed to share via WhatsApp: $e');
    }
  }

  /// Shares multiple image files via share intent
  /// Works with XFile on all platforms (iOS, Android, Web)
  /// 
  /// For iOS: Pass [sharePositionOrigin] to position the share sheet properly
  Future<void> shareMultipleImages(
    List<XFile> imageFiles, {
    String? text,
    Rect? sharePositionOrigin,
  }) async {
    if (imageFiles.isEmpty) {
      throw ShareException('No images to share');
    }
    
    try {
      final origin = sharePositionOrigin ?? _getDefaultSharePosition();
      
      await SharePlus.instance.share(
        ShareParams(
          files: imageFiles,
          text: text ?? 'Check out my ${imageFiles.length} AI generated photo${imageFiles.length > 1 ? 's' : ''}!',
          subject: '${AppConstants.kBrandName} images',
          sharePositionOrigin: origin,
        ),
      );
    } catch (e) {
      throw ShareException('Failed to share images: $e');
    }
  }

  /// Get default share position (center of screen)
  /// Used when sharePositionOrigin is not provided on iOS
  Rect _getDefaultSharePosition() {
    // Get screen size from PlatformDispatcher
    final view = PlatformDispatcher.instance.views.isEmpty
        ? null
        : PlatformDispatcher.instance.views.first;
    if (view == null) {
      // Fallback: a 1×1 rect at origin. Share sheet positioning is best-effort
      // when no view is available; the share UI still functions.
      return const Rect.fromLTWH(0, 0, 1, 1);
    }
    final size = view.physicalSize / view.devicePixelRatio;
    
    // Return a rect in the center of the screen
    return Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: 1,
      height: 1,
    );
  }
}

