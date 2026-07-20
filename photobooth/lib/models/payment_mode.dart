/// Settlement mode captured when staff/admin approve a payment.
enum PaymentMode {
  upi,
  cash,
  complimentary;

  /// API wire values: `UPI` | `CASH` | `COMPLIMENTARY`.
  String get apiValue {
    switch (this) {
      case PaymentMode.upi:
        return 'UPI';
      case PaymentMode.cash:
        return 'CASH';
      case PaymentMode.complimentary:
        return 'COMPLIMENTARY';
    }
  }

  /// Human label for staff dropdown / history badge.
  String get label => apiValue;

  static const List<PaymentMode> apiOrder = [
    PaymentMode.upi,
    PaymentMode.cash,
    PaymentMode.complimentary,
  ];

  /// Parses API / payload strings; unknown → null.
  static PaymentMode? tryParse(String? raw) {
    final t = (raw ?? '').trim().toUpperCase();
    if (t.isEmpty) return null;
    switch (t) {
      case 'UPI':
        return PaymentMode.upi;
      case 'CASH':
        return PaymentMode.cash;
      case 'COMPLIMENTARY':
      case 'COMP':
      case 'FREE':
        return PaymentMode.complimentary;
      default:
        return null;
    }
  }

  /// Default approve mode: complimentary when amount ≤ 0, else UPI.
  static PaymentMode defaultForAmount(num? amount) {
    final a = amount ?? 0;
    return a <= 0 ? PaymentMode.complimentary : PaymentMode.upi;
  }
}
