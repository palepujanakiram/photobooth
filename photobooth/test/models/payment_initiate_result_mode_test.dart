import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/payment_initiate_result.dart';
import 'package:photobooth/models/payment_mode.dart';

void main() {
  test('parses paymentMode', () {
    final r = PaymentInitiateResult.fromJson({
      'id': 'pay-1',
      'status': 'PENDING',
      'paymentMode': 'UPI',
    });
    expect(r.paymentMode, PaymentMode.upi);
  });
}
