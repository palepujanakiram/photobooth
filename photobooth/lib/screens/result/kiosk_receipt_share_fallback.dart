/// Receipt share fields + setters for kiosk fallback (Sonar S107).
class KioskReceiptShareFallback {
  const KioskReceiptShareFallback({
    required this.receiptShareUrl,
    required this.kioskFallbackShareUrl,
    required this.setReceiptShareUrl,
    required this.receiptShareLongUrl,
    required this.kioskFallbackShareLongUrl,
    required this.setReceiptShareLongUrl,
    required this.receiptShareExpiresAt,
    required this.kioskFallbackShareExpiresAt,
    required this.setReceiptShareExpiresAt,
  });

  final String? receiptShareUrl;
  final String? kioskFallbackShareUrl;
  final void Function(String url) setReceiptShareUrl;
  final String? receiptShareLongUrl;
  final String? kioskFallbackShareLongUrl;
  final void Function(String longUrl) setReceiptShareLongUrl;
  final DateTime? receiptShareExpiresAt;
  final DateTime? kioskFallbackShareExpiresAt;
  final void Function(DateTime expiresAt) setReceiptShareExpiresAt;
}
