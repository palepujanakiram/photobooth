import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/payment_initiate_result.dart';
import 'package:photobooth/screens/result/result_payment_poll_helpers.dart';

void main() {
  test('shouldPollPaymentStatus is true only with a non-blank payment id', () {
    expect(shouldPollPaymentStatus(null), isFalse);
    expect(shouldPollPaymentStatus(''), isFalse);
    expect(shouldPollPaymentStatus('  '), isFalse);
    expect(shouldPollPaymentStatus('pay-1'), isTrue);
  });

  test('shouldFallbackToSessionPoll after status-pending ticks', () {
    expect(
      shouldFallbackToSessionPoll(kPaymentPollStatusFallbackTicks - 1),
      isFalse,
    );
    expect(
      shouldFallbackToSessionPoll(kPaymentPollStatusFallbackTicks),
      isTrue,
    );
    expect(
      sessionIdForPaymentStatusFallback(
        paymentStatusTicks: kPaymentPollStatusFallbackTicks,
        sessionId: ' sess-1 ',
      ),
      'sess-1',
    );
    expect(
      sessionIdForPaymentStatusFallback(
        paymentStatusTicks: kPaymentPollStatusFallbackTicks,
        sessionId: '  ',
      ),
      isNull,
    );
  });

  test('isPaymentStatusPollActive is false after session fallback', () {
    expect(
      isPaymentStatusPollActive(paymentId: 'pay-1', sessionFallback: false),
      isTrue,
    );
    expect(
      isPaymentStatusPollActive(paymentId: 'pay-1', sessionFallback: true),
      isFalse,
    );
  });

  test('isPaymentPollDead uses the active poller streak', () {
    expect(
      isPaymentPollDead(
        outcomeHandled: true,
        fcmPaymentPushSuccess: null,
        paymentId: 'pay-1',
        sessionFallback: false,
        paymentStatusFailures: 99,
        sessionFailures: 99,
      ),
      isFalse,
    );
    expect(
      isPaymentPollDead(
        outcomeHandled: false,
        fcmPaymentPushSuccess: true,
        paymentId: 'pay-1',
        sessionFallback: false,
        paymentStatusFailures: 99,
        sessionFailures: 99,
      ),
      isFalse,
    );
    expect(
      isPaymentPollDead(
        outcomeHandled: false,
        fcmPaymentPushSuccess: null,
        paymentId: 'pay-1',
        sessionFallback: false,
        paymentStatusFailures: kPaymentPollDeadFailureTicks,
        sessionFailures: 0,
      ),
      isTrue,
    );
    expect(
      isPaymentPollDead(
        outcomeHandled: false,
        fcmPaymentPushSuccess: null,
        paymentId: null,
        sessionFallback: false,
        paymentStatusFailures: 0,
        sessionFailures: kPaymentPollDeadFailureTicks,
      ),
      isTrue,
    );
    expect(
      isPaymentPollDead(
        outcomeHandled: false,
        fcmPaymentPushSuccess: null,
        paymentId: 'pay-1',
        sessionFallback: false,
        paymentStatusFailures: kPaymentPollDeadFailureTicks - 1,
        sessionFailures: 99,
      ),
      isFalse,
    );
    expect(
      isPaymentPollDead(
        outcomeHandled: false,
        fcmPaymentPushSuccess: null,
        paymentId: 'pay-1',
        sessionFallback: true,
        paymentStatusFailures: 0,
        sessionFailures: kPaymentPollDeadFailureTicks,
      ),
      isTrue,
    );
  });

  test('paymentQrPayloadPresent detects any scannable field', () {
    expect(paymentQrPayloadPresent(), isFalse);
    expect(
      paymentQrPayloadPresent(paymentLink: 'https://pay.example'),
      isTrue,
    );
    expect(
      paymentQrPayloadPresent(qrImageUrl: 'https://rzp.io/q.png'),
      isTrue,
    );
    expect(
      paymentQrPayloadPresent(upiLink: 'upi://pay?pa=x'),
      isTrue,
    );
  });

  test('paymentVerdictFromStatusString maps created and active to pending', () {
    expect(
      paymentVerdictFromStatusString('CREATED'),
      PaymentPollVerdict.pending,
    );
    expect(
      paymentVerdictFromStatusString('ACTIVE'),
      PaymentPollVerdict.pending,
    );
  });

  test('paymentVerdictFromPaymentStatusResponse reads status field', () {
    expect(
      paymentVerdictFromPaymentStatusResponse({'status': 'FAILED'}),
      PaymentPollVerdict.failed,
    );
  });

  test('paymentVerdictFromSession ignores session lifecycle status', () {
    expect(
      paymentVerdictFromSession({'status': 'CONFIRMED'}),
      isNull,
    );
    expect(
      paymentVerdictFromSession({'status': 'IMAGE_GENERATED'}),
      isNull,
    );
    expect(
      paymentVerdictFromSession({'paymentStatus': 'PENDING'}),
      PaymentPollVerdict.pending,
    );
    expect(
      paymentVerdictFromSession({'paymentStatus': 'APPROVED'}),
      PaymentPollVerdict.approved,
    );
    expect(
      paymentVerdictFromSession({
        'payment': {'status': 'PAID'},
      }),
      PaymentPollVerdict.approved,
    );
  });

  test('PaymentInitiateResult parses Cashfree-style aliases', () {
    final r = PaymentInitiateResult.fromJson({
      'payment_id': 'pay-1',
      'payment_url': 'https://payments.cashfree.com/order/x',
      'qr_code': 'https://rzp.io/q.png',
    });
    expect(r.id, 'pay-1');
    expect(r.paymentLink, 'https://payments.cashfree.com/order/x');
    expect(r.qrImageUrl, 'https://rzp.io/q.png');
  });
}
