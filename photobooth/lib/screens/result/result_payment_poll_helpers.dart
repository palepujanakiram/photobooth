/// Payment polling helpers for the Pay screen (session + payment status).
enum PaymentPollVerdict { approved, failed, pending }

/// FCM is the primary Pay signal. This is the HTTP backup cadence.
const Duration kPaymentPollInterval = Duration(seconds: 8);

/// Wall-clock cap at [kPaymentPollInterval] (~12 minutes).
const int kPaymentPollMaxTicks = 90;

/// Consecutive failed GETs before the Pay screen shows a stuck fallback (~32s).
const int kPaymentPollDeadFailureTicks = 4;

/// PENDING `/payments/status` ticks before switching to the session GET (~64s).
///
/// Razorpay can mark the session paid while the payment-status row stays PENDING.
const int kPaymentPollStatusFallbackTicks = 8;

/// UPI: poll `GET /api/payments/status`. Cash / missing id: poll the session.
bool shouldPollPaymentStatus(String? paymentId) {
  final id = paymentId?.trim();
  return id != null && id.isNotEmpty;
}

/// True after enough PENDING payment-status ticks to try the session instead.
bool shouldFallbackToSessionPoll(int paymentStatusTicks) {
  return paymentStatusTicks >= kPaymentPollStatusFallbackTicks;
}

/// Session id to switch to after pending `/payments/status`, or null to keep it.
String? sessionIdForPaymentStatusFallback({
  required int paymentStatusTicks,
  required String? sessionId,
}) {
  if (!shouldFallbackToSessionPoll(paymentStatusTicks)) return null;
  final id = sessionId?.trim();
  if (id == null || id.isEmpty) return null;
  return id;
}

/// UPI status poller is running (not cash and not post-fallback session).
bool isPaymentStatusPollActive({
  required String? paymentId,
  required bool sessionFallback,
}) {
  return shouldPollPaymentStatus(paymentId) && !sessionFallback;
}

/// Stuck-fallback visibility for whichever backup poller is active.
bool isPaymentPollDead({
  required bool outcomeHandled,
  required bool? fcmPaymentPushSuccess,
  required String? paymentId,
  required bool sessionFallback,
  required int paymentStatusFailures,
  required int sessionFailures,
}) {
  if (outcomeHandled) return false;
  if (fcmPaymentPushSuccess != null) return false;
  if (isPaymentStatusPollActive(
    paymentId: paymentId,
    sessionFallback: sessionFallback,
  )) {
    return paymentStatusFailures >= kPaymentPollDeadFailureTicks;
  }
  return sessionFailures >= kPaymentPollDeadFailureTicks;
}

/// True when any field can render a scannable UPI QR on the Pay screen.
bool paymentQrPayloadPresent({
  String? qrImageUrl,
  String? upiLink,
  String? paymentLink,
}) {
  bool has(String? s) => s != null && s.trim().isNotEmpty;
  return has(qrImageUrl) || has(upiLink) || has(paymentLink);
}

/// Maps payment status strings from the API to a poll verdict.
PaymentPollVerdict? paymentVerdictFromStatusString(String? raw) {
  final s = raw?.trim().toUpperCase();
  if (s == null || s.isEmpty) return null;
  switch (s) {
    case 'APPROVED':
    case 'PAID':
    case 'CONFIRMED':
    case 'SUCCESS':
    case 'SUCCESSFUL':
      return PaymentPollVerdict.approved;
    case 'FAILED':
    case 'DECLINED':
    case 'REJECTED':
    case 'CANCELLED':
    case 'CANCELED':
      return PaymentPollVerdict.failed;
    case 'PENDING':
    case 'CREATED':
    case 'ACTIVE':
      return PaymentPollVerdict.pending;
    default:
      return PaymentPollVerdict.pending;
  }
}

dynamic _pick(Map<String, dynamic> raw, List<String> keys) {
  for (final k in keys) {
    if (raw.containsKey(k)) return raw[k];
  }
  return null;
}

Map<String, dynamic>? _asStringKeyedMap(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return Map<String, dynamic>.from(v);
  return null;
}

/// Session poll verdict — uses **payment** fields only, not session lifecycle `status`.
PaymentPollVerdict? paymentVerdictFromSession(Map<String, dynamic> raw) {
  final paidFlag = _pick(raw, const [
    'paymentApproved',
    'payment_approved',
    'isPaid',
    'paid',
    'paymentConfirmed',
  ]);
  if (paidFlag is bool) {
    return paidFlag
        ? PaymentPollVerdict.approved
        : PaymentPollVerdict.pending;
  }

  final paymentStatus = _pick(raw, const [
    'paymentStatus',
    'payment_status',
  ])?.toString();
  final fromPaymentStatus = paymentVerdictFromStatusString(paymentStatus);
  if (fromPaymentStatus != null &&
      paymentStatus != null &&
      paymentStatus.trim().isNotEmpty) {
    return fromPaymentStatus;
  }

  final payment = _asStringKeyedMap(raw['payment']);
  if (payment != null) {
    final nestedStatus = payment['status']?.toString();
    final nested = paymentVerdictFromStatusString(nestedStatus);
    if (nested != null &&
        nestedStatus != null &&
        nestedStatus.trim().isNotEmpty) {
      return nested;
    }
  }

  return null;
}

PaymentPollVerdict? paymentVerdictFromPaymentStatusResponse(
  Map<String, dynamic> raw,
) {
  return paymentVerdictFromStatusString(raw['status']?.toString());
}
