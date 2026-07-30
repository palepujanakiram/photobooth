import '../result/result_viewmodel.dart';

/// Share-screen fields that should trigger a UI rebuild (excludes print progress).
class QrShareUiSnapshot {
  const QrShareUiSnapshot({
    required this.qrData,
    required this.longUrl,
    this.expiresAt,
    required this.headline,
    required this.waLine,
  });

  final String qrData;
  final String longUrl;
  final DateTime? expiresAt;
  final String headline;
  final String waLine;

  factory QrShareUiSnapshot.fromViewModel({
    required ResultViewModel viewModel,
    required String? parsedShareUrl,
    required String? parsedKioskShareUrl,
    required String? parsedShareLongUrl,
    required DateTime? parsedShareExpiresAt,
    required String phone,
  }) {
    final qrData = resolveQrShareData(
      receiptShareUrl: viewModel.receiptShareUrl,
      kioskFallbackShareUrl: viewModel.kioskFallbackShareUrl,
      parsedShareUrl: parsedShareUrl,
      parsedKioskShareUrl: parsedKioskShareUrl,
    );
    final longUrl = resolveQrShareLongUrl(
      receiptShareLongUrl: viewModel.receiptShareLongUrl,
      parsedShareLongUrl: parsedShareLongUrl,
    );
    final expiresAt = resolveQrShareExpiresAt(
      receiptShareExpiresAt: viewModel.receiptShareExpiresAt,
      parsedShareExpiresAt: parsedShareExpiresAt,
    );
    final waActuallyQueued = viewModel.whatsappQueued;
    final waRequested = viewModel.effectiveWhatsappOptIn;
    final vmStatus = (viewModel.whatsappDeliveryStatus ?? '').trim();
    return QrShareUiSnapshot(
      qrData: qrData,
      longUrl: longUrl,
      expiresAt: expiresAt,
      headline: qrShareHeadline(
        waActuallyQueued: waActuallyQueued,
        phone: phone,
      ),
      waLine: qrShareWhatsappLine(
        waActuallyQueued: waActuallyQueued,
        vmStatus: vmStatus,
        waRequested: waRequested,
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is QrShareUiSnapshot &&
        qrData == other.qrData &&
        longUrl == other.longUrl &&
        expiresAt == other.expiresAt &&
        headline == other.headline &&
        waLine == other.waLine;
  }

  @override
  int get hashCode => Object.hash(qrData, longUrl, expiresAt, headline, waLine);
}

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
