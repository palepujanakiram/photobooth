import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/payment_mode.dart';

void main() {
  test('apiValue and tryParse round-trip', () {
    expect(PaymentMode.upi.apiValue, 'UPI');
    expect(PaymentMode.cash.apiValue, 'CASH');
    expect(PaymentMode.complimentary.apiValue, 'COMPLIMENTARY');
    expect(PaymentMode.tryParse('upi'), PaymentMode.upi);
    expect(PaymentMode.tryParse('CASH'), PaymentMode.cash);
    expect(PaymentMode.tryParse('COMP'), PaymentMode.complimentary);
    expect(PaymentMode.tryParse('FREE'), PaymentMode.complimentary);
    expect(PaymentMode.tryParse('nope'), isNull);
    expect(PaymentMode.tryParse(null), isNull);
  });

  test('defaultForAmount', () {
    expect(PaymentMode.defaultForAmount(0), PaymentMode.complimentary);
    expect(PaymentMode.defaultForAmount(-1), PaymentMode.complimentary);
    expect(PaymentMode.defaultForAmount(100), PaymentMode.upi);
    expect(PaymentMode.defaultForAmount(null), PaymentMode.complimentary);
  });

  test('label matches apiValue', () {
    for (final m in PaymentMode.apiOrder) {
      expect(m.label, m.apiValue);
    }
  });
}
