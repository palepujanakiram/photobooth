import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/session_discount.dart';

void main() {
  test('fromApplyResponse parses nested coupon', () {
    final d = SessionDiscount.fromApplyResponse({
      'coupon': {'code': 'FEST20'},
      'discountAmount': 50,
      'finalAmount': 200,
      'subtotal': 250,
    });
    expect(d.code, 'FEST20');
    expect(d.discountAmount, 50);
    expect(d.finalAmount, 200);
    expect(d.chargeAmount, 200);
  });

  test('fromApplyResponse falls back to root code fields', () {
    final d = SessionDiscount.fromApplyResponse({
      'code': 'ROOT',
      'discountAmount': '10',
      'finalAmount': 90.4,
      'subtotal': 100,
    });
    expect(d.code, 'ROOT');
    expect(d.discountAmount, 10);
    expect(d.finalAmount, 90);
  });

  test('fromApplyResponse uses appliedCouponCode', () {
    final d = SessionDiscount.fromApplyResponse({
      'appliedCouponCode': 'APP',
      'discountAmount': 1,
      'finalAmount': 2,
      'subtotal': 3,
    });
    expect(d.code, 'APP');
  });

  test('fromGetResponse when applied', () {
    final d = SessionDiscount.fromGetResponse({
      'applied': true,
      'coupon': {'code': 'SAVE'},
      'subtotal': 100,
      'discountAmount': 20,
      'finalAmount': 80,
    });
    expect(d?.code, 'SAVE');
    expect(d?.chargeAmount, 80);
  });

  test('fromGetResponse computes finalAmount when missing', () {
    final d = SessionDiscount.fromGetResponse({
      'applied': true,
      'coupon': {'code': 'SAVE'},
      'subtotal': 100,
      'discountAmount': 25,
    });
    expect(d?.finalAmount, 75);
  });

  test('fromGetResponse when not applied', () {
    expect(
      SessionDiscount.fromGetResponse({'applied': false}),
      isNull,
    );
  });

  test('chargeAmount clamps negative final', () {
    const d = SessionDiscount(
      code: 'X',
      discountAmount: 10,
      finalAmount: -5,
      subtotal: 10,
    );
    expect(d.chargeAmount, 0);
  });
}
