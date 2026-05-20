/// Response from POST /api/payment/initiate
class PaymentInitiateResult {
  PaymentInitiateResult({
    required this.id,
    this.paymentLink,
    this.qrImageUrl,
    this.upiLink,
    required this.status,
  });

  final String id;
  /// Hosted checkout URL (HTTPS) — last-resort QR payload when UPI intent / PNG absent.
  final String? paymentLink;
  /// Razorpay-hosted vertical QR PNG (`https://rzp.io/...`).
  final String? qrImageUrl;
  /// `upi://pay?pa=...` when Razorpay UPI Intent is enabled (often null today).
  final String? upiLink;
  final String status;

  /// Non-empty string from [v], or null.
  static String? _coerceString(dynamic v) {
    if (v == null) return null;
    if (v is String) {
      final t = v.trim();
      return t.isEmpty ? null : t;
    }
    final t = v.toString().trim();
    return t.isEmpty ? null : t;
  }

  /// First non-empty string for any of [keys] on [m].
  static String? _pick(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final s = _coerceString(m[k]);
      if (s != null) return s;
    }
    return null;
  }

  /// Merges `data` and nested `payment` maps so fields can live on the root,
  /// under `data`, or only on `payment` (matches common API + snake_case JSON).
  static Map<String, dynamic> _effectiveFields(Map<String, dynamic> json) {
    final out = Map<String, dynamic>.from(json);

    void mergeMap(dynamic src) {
      if (src is Map<String, dynamic>) {
        for (final e in src.entries) {
          out.putIfAbsent(e.key, () => e.value);
        }
      } else if (src is Map) {
        final pm = Map<String, dynamic>.from(src);
        for (final e in pm.entries) {
          out.putIfAbsent(e.key, () => e.value);
        }
      }
    }

    mergeMap(json['data']);
    mergeMap(json['payment']);

    final nestedPayment = out['payment'];
    mergeMap(nestedPayment);

    return out;
  }

  factory PaymentInitiateResult.fromJson(Map<String, dynamic> json) {
    final m = _effectiveFields(json);
    return PaymentInitiateResult(
      id: _pick(m, const ['id', 'paymentId', 'payment_id']) ?? '',
      paymentLink: _pick(m, const ['paymentLink', 'payment_link']),
      qrImageUrl: _pick(m, const [
        'qrImageUrl',
        'qr_image_url',
        'hostedQrUrl',
        'hosted_qr_url',
        'qrUrl',
        'qr_url',
      ]),
      upiLink: _pick(m, const ['upiLink', 'upi_link']),
      status: _pick(m, const ['status', 'payment_status']) ?? 'PENDING',
    );
  }
}
