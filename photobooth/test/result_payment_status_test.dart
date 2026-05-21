import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/result/result_payment_status.dart';

void main() {
  test('computePaymentCardHeight clamps finite constraints', () {
    expect(
      computePaymentCardHeight(const BoxConstraints(maxHeight: 500)),
      500,
    );
    expect(
      computePaymentCardHeight(const BoxConstraints(maxHeight: 100)),
      260,
    );
    expect(
      computePaymentCardHeight(const BoxConstraints()),
      420,
    );
  });
}
