import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/payment_initiate_result.dart';
import 'package:photobooth/screens/result/result_payment_poll_helpers.dart';

void main() {
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
