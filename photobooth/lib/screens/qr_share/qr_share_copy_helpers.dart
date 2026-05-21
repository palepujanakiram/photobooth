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
