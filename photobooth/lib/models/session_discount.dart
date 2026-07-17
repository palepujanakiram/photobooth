/// Applied session coupon from discount apply/get APIs.
class SessionDiscount {
  const SessionDiscount({
    required this.code,
    required this.discountAmount,
    required this.finalAmount,
    required this.subtotal,
  });

  final String code;
  final int discountAmount;
  final int finalAmount;
  final int subtotal;

  /// Amount to charge after discount (never negative).
  int get chargeAmount => finalAmount < 0 ? 0 : finalAmount;

  factory SessionDiscount.fromApplyResponse(Map<String, dynamic> json) {
    final coupon = json['coupon'];
    var code = '';
    if (coupon is Map) {
      code = (coupon['code'] ?? '').toString().trim();
    }
    if (code.isEmpty) {
      code = (json['appliedCouponCode'] ?? json['code'] ?? '').toString().trim();
    }
    return SessionDiscount(
      code: code,
      discountAmount: _asInt(json['discountAmount']) ?? 0,
      finalAmount: _asInt(json['finalAmount']) ?? 0,
      subtotal: _asInt(json['subtotal']) ?? 0,
    );
  }

  /// Builds from GET `/api/sessions/:id/discount` when `applied` is true.
  static SessionDiscount? fromGetResponse(Map<String, dynamic> json) {
    if (json['applied'] != true) return null;
    final coupon = json['coupon'];
    var code = '';
    if (coupon is Map) {
      code = (coupon['code'] ?? '').toString().trim();
    }
    if (code.isEmpty) return null;
    final subtotal = _asInt(json['subtotal']) ?? 0;
    final discountAmount = _asInt(json['discountAmount']) ?? 0;
    final finalAmount = _asInt(json['finalAmount']) ??
        (subtotal - discountAmount).clamp(0, 1 << 30);
    return SessionDiscount(
      code: code,
      discountAmount: discountAmount,
      finalAmount: finalAmount,
      subtotal: subtotal,
    );
  }

  static int? _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.round();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }
}
