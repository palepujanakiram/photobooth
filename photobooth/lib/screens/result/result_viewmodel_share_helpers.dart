import 'package:flutter/services.dart';

import '../../utils/constants.dart';
import '../../utils/exceptions.dart';
import 'kiosk_receipt_share_fallback.dart';

/// Post-payment share + share-images helpers (Sonar S3776 extractions).
void applyKioskFallbackWhenReceiptShareEmpty(KioskReceiptShareFallback state) {
  final ru = state.receiptShareUrl?.trim() ?? '';
  if (ru.isNotEmpty) return;
  final ku = state.kioskFallbackShareUrl?.trim() ?? '';
  if (ku.isEmpty) return;
  state.setReceiptShareUrl(state.kioskFallbackShareUrl!);
  if ((state.receiptShareLongUrl?.trim() ?? '').isEmpty &&
      state.kioskFallbackShareLongUrl != null) {
    state.setReceiptShareLongUrl(state.kioskFallbackShareLongUrl!);
  }
  if (state.receiptShareExpiresAt == null &&
      state.kioskFallbackShareExpiresAt != null) {
    state.setReceiptShareExpiresAt(state.kioskFallbackShareExpiresAt!);
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
