/// Response from POST /api/payment/initiate
class PaymentInitiateResult {
  PaymentInitiateResult({
    required this.id,
    this.paymentLink,
    required this.status,
  });

  final String id;
  /// UPI deep link to encode as QR (may be null/empty for manual/static QR mode).
  final String? paymentLink;
  final String status;

  factory PaymentInitiateResult.fromJson(Map<String, dynamic> json) {
    final link = (json['paymentLink'] as String?)?.trim();
    return PaymentInitiateResult(
      id: json['id'] as String? ?? '',
      paymentLink: (link != null && link.isNotEmpty) ? link : null,
      status: json['status'] as String? ?? 'PENDING',
    );
  }
}
