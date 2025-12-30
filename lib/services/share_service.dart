import 'package:share_plus/share_plus.dart';
import '../utils/exceptions.dart';

class ShareService {
  /// Shares an image file via WhatsApp or other sharing options
  /// Works with XFile on all platforms (iOS, Android, Web)
  Future<void> shareImage(XFile imageFile, {String? text}) async {
    try {
      await Share.shareXFiles(
        [imageFile],
        text: text,
        subject: 'Photo Booth Image',
      );
    } catch (e) {
      throw ShareException('Failed to share image: $e');
    }
  }

  /// Shares an image specifically via WhatsApp
  /// Works with XFile on all platforms (iOS, Android, Web)
  Future<void> shareViaWhatsApp(XFile imageFile, {String? text}) async {
    try {
      await Share.shareXFiles(
        [imageFile],
        text: text ?? 'Check out my photo!',
        subject: 'Photo Booth Image',
      );
    } catch (e) {
      throw ShareException('Failed to share via WhatsApp: $e');
    }
  }
}

