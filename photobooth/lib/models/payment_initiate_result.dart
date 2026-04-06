/// Response from POST /api/payment/initiate
class PaymentInitiateResult {
  PaymentInitiateResult({
    required this.id,
    required this.paymentLink,
    required this.status,
  });

  final String id;
  final String paymentLink;
  final String status;

  factory PaymentInitiateResult.fromJson(Map<String, dynamic> json) {
    final link = json['paymentLink'] as String?;
    if (link == null || link.isEmpty) {
      throw const FormatException(
        'paymentLink missing in payment initiate response',
      );
    }
    return PaymentInitiateResult(
      id: json['id'] as String? ?? '',
      paymentLink: link,
      status: json['status'] as String? ?? 'PENDING',
    );
  }
}
