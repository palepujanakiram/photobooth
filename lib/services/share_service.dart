import 'dart:io';
import 'package:share_plus/share_plus.dart';
import '../utils/exceptions.dart';

class ShareService {
  /// Shares an image file via WhatsApp or other sharing options
  Future<void> shareImage(File imageFile, {String? text}) async {
    try {
      final xFile = XFile(imageFile.path);
      await Share.shareXFiles(
        [xFile],
        text: text,
        subject: 'Photo Booth Image',
      );
    } catch (e) {
      throw ShareException('Failed to share image: $e');
    }
  }

  /// Shares an image specifically via WhatsApp
  Future<void> shareViaWhatsApp(File imageFile, {String? text}) async {
    try {
      final xFile = XFile(imageFile.path);
      await Share.shareXFiles(
        [xFile],
        text: text ?? 'Check out my photo!',
        subject: 'Photo Booth Image',
      );
    } catch (e) {
      throw ShareException('Failed to share via WhatsApp: $e');
    }
  }
}

