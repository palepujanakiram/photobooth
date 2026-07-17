import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/customer_contact_capture.dart';

void main() {
  test('toRouteArgsMap and tryParseRouteMap', () {
    const c = CustomerContactCapture(
      customerName: 'Ada',
      customerPhone: '+919876543210',
      whatsappOptIn: true,
      customerEmail: 'a@b.co',
      customerUpiVpa: 'ada@upi',
      marketingEmailOptIn: true,
      marketingSmsOptIn: true,
      marketingWhatsappOptIn: false,
    );
    final map = c.toRouteArgsMap();
    final parsed = CustomerContactCapture.tryParseRouteMap(map);
    expect(parsed.customerName, 'Ada');
    expect(parsed.customerPhone, '+919876543210');
    expect(parsed.whatsappOptIn, isTrue);
    expect(parsed.customerEmail, 'a@b.co');
    expect(parsed.customerUpiVpa, 'ada@upi');
    expect(parsed.marketingEmailOptIn, isTrue);
    expect(parsed.marketingSmsOptIn, isTrue);
    expect(parsed.marketingWhatsappOptIn, isFalse);
  });

  test('copyWith preserves unspecified fields', () {
    const c = CustomerContactCapture(
      customerName: 'Ada',
      marketingSmsOptIn: true,
      skipped: false,
    );
    final next = c.copyWith(customerPhone: '+91');
    expect(next.customerName, 'Ada');
    expect(next.customerPhone, '+91');
    expect(next.marketingSmsOptIn, isTrue);
    expect(next.skipped, isFalse);
  });

  test('copyWith overrides marketing and skipped', () {
    const c = CustomerContactCapture.empty;
    final next = c.copyWith(skipped: true, marketingSmsOptIn: true);
    expect(next.skipped, isTrue);
    expect(next.marketingSmsOptIn, isTrue);
  });
}
