import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/payment.dart';
import 'package:photobooth/models/payment_mode.dart';

void main() {
  test('Payment.fromJson picks mode and amount', () {
    final p = Payment.fromJson({
      'id': 'pay-1',
      'status': 'pending',
      'sessionId': 'sess-1',
      'amount': 250,
      'paymentMode': 'CASH',
    });
    expect(p.id, 'pay-1');
    expect(p.status, 'PENDING');
    expect(p.sessionId, 'sess-1');
    expect(p.amount, 250);
    expect(p.paymentMode, PaymentMode.cash);
  });

  test('Payment.fromJson nested session', () {
    final p = Payment.fromJson({
      'paymentId': 'pay-2',
      'session': {'id': 'sess-2'},
      'total': '100',
    });
    expect(p.id, 'pay-2');
    expect(p.sessionId, 'sess-2');
    expect(p.amount, 100);
  });
}
