import 'package:flutter/services.dart';

import '../../utils/constants.dart';
import '../../utils/exceptions.dart';

/// Post-payment share + share-images helpers (Sonar S3776 extractions).
void applyKioskFallbackWhenReceiptShareEmpty({
  required String? receiptShareUrl,
  required String? kioskFallbackShareUrl,
  required void Function(String url) setReceiptShareUrl,
  required String? receiptShareLongUrl,
  required String? kioskFallbackShareLongUrl,
  required void Function(String longUrl) setReceiptShareLongUrl,
  required DateTime? receiptShareExpiresAt,
  required DateTime? kioskFallbackShareExpiresAt,
  required void Function(DateTime expiresAt) setReceiptShareExpiresAt,
}) {
  final ru = receiptShareUrl?.trim() ?? '';
  if (ru.isNotEmpty) return;
  final ku = kioskFallbackShareUrl?.trim() ?? '';
  if (ku.isEmpty) return;
  setReceiptShareUrl(kioskFallbackShareUrl!);
  if ((receiptShareLongUrl?.trim() ?? '').isEmpty &&
      kioskFallbackShareLongUrl != null) {
    setReceiptShareLongUrl(kioskFallbackShareLongUrl);
  }
  if (receiptShareExpiresAt == null && kioskFallbackShareExpiresAt != null) {
    setReceiptShareExpiresAt(kioskFallbackShareExpiresAt);
  }
}

/// Web share path: join image URLs as text.
Future<String?> shareGeneratedImageUrlsOnWeb({
  required List<String> urls,
  required Future<void> Function(
    String text, {
    Rect? sharePositionOrigin,
    String? subject,
  }) shareText,
  Rect? sharePositionOrigin,
}) async {
  if (urls.isEmpty) return 'No images to share';
  try {
    await shareText(
      urls.join('\n'),
      sharePositionOrigin: sharePositionOrigin,
      subject: '${AppConstants.kBrandName} photos',
    );
    return null;
  } on ShareException {
    try {
      await Clipboard.setData(ClipboardData(text: urls.join('\n')));
      return 'Sharing not supported in this browser. Link copied.';
    } catch (_) {
      return 'Failed to share';
    }
  } catch (e) {
    return 'Failed to share: $e';
  }
}
