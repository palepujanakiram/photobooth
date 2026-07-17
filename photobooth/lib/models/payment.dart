import 'payment_mode.dart';

/// Staff/admin payment row fields we care about in the kiosk app.
class Payment {
  const Payment({
    required this.id,
    this.status = '',
    this.sessionId = '',
    this.amount,
    this.paymentMode,
  });

  final String id;
  final String status;
  final String sessionId;
  final num? amount;
  final PaymentMode? paymentMode;

  factory Payment.fromJson(Map<String, dynamic> json) {
    final id = _pickString(json, const ['id', 'paymentId', 'payment_id']);
    final status =
        _pickString(json, const ['status', 'paymentStatus', 'payment_status'])
            .toUpperCase();
    final sessionId = _pickSessionId(json);
    final amount = _pickAmount(json);
    final mode = PaymentMode.tryParse(
      _pickString(json, const ['paymentMode', 'payment_mode']),
    );
    return Payment(
      id: id,
      status: status,
      sessionId: sessionId,
      amount: amount,
      paymentMode: mode,
    );
  }

  static String _pickString(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  static String _pickSessionId(Map<String, dynamic> m) {
    final direct = _pickString(m, const ['sessionId', 'session_id']);
    if (direct.isNotEmpty) return direct;
    final sessionObj = m['session'];
    if (sessionObj is Map) {
      return _pickString(
        Map<String, dynamic>.from(sessionObj),
        const ['id', 'sessionId', 'session_id'],
      );
    }
    return '';
  }

  static num? _pickAmount(Map<String, dynamic> m) {
    for (final k in const ['amount', 'total', 'price']) {
      final v = m[k];
      if (v is num) return v;
      if (v is String) {
        final n = num.tryParse(v.trim());
        if (n != null) return n;
      }
    }
    return null;
  }
}
