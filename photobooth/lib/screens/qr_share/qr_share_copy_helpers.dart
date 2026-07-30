import '../result/result_viewmodel.dart';

/// QR share screen copy (Sonar S3358 / S3776 extractions).
String qrShareHeadline({
  required bool waActuallyQueued,
  required String phone,
}) {
  if (waActuallyQueued && phone.isNotEmpty) {
    return 'We also sent your receipt and digital copy to $phone on WhatsApp. '
        'Anyone can still scan this QR to download a digital copy.';
  }
  return 'Scan this QR on your phone to download a digital copy.';
}

String qrShareWhatsappLine({
  required bool waActuallyQueued,
  required String vmStatus,
  required bool waRequested,
}) {
  if (!waActuallyQueued) return '';
  if (vmStatus.isNotEmpty) {
    return 'WhatsApp: ${ResultViewModel.friendlyWhatsappStatus(vmStatus)}';
  }
  if (waRequested) return 'WhatsApp: Updating…';
  return '';
}

String qrShareExpiryText(DateTime? expiresAt) {
  if (expiresAt == null) return '';
  final local = expiresAt.toLocal();
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return 'Link expires at $hh:$mm';
}

/// Prefer live [ResultViewModel] share fields; fall back to route args from Pay.
String resolveQrShareData({
  required String? receiptShareUrl,
  required String? kioskFallbackShareUrl,
  required String? parsedShareUrl,
  required String? parsedKioskShareUrl,
}) {
  final shareUrl = (receiptShareUrl ?? parsedShareUrl ?? '').trim();
  final kioskUrl = (kioskFallbackShareUrl ?? parsedKioskShareUrl ?? '').trim();
  return shareUrl.isNotEmpty ? shareUrl : kioskUrl;
}

String resolveQrShareLongUrl({
  required String? receiptShareLongUrl,
  required String? parsedShareLongUrl,
}) {
  return (receiptShareLongUrl ?? parsedShareLongUrl ?? '').trim();
}

DateTime? resolveQrShareExpiresAt({
  required DateTime? receiptShareExpiresAt,
  required DateTime? parsedShareExpiresAt,
}) {
  return receiptShareExpiresAt ?? parsedShareExpiresAt;
}
