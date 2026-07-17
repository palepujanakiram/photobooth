import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/utils/contact_phone_helpers.dart';

void main() {
  test('normalizePhone India defaults', () {
    expect(ContactPhoneHelpers.normalizePhone('9876543210'), '+919876543210');
    expect(ContactPhoneHelpers.normalizePhone('09876543210'), '+919876543210');
    expect(ContactPhoneHelpers.normalizePhone('919876543210'), '+919876543210');
    expect(ContactPhoneHelpers.normalizePhone('+1 234 567 8901'), '+12345678901');
    expect(ContactPhoneHelpers.normalizePhone(''), '');
  });

  test('isValidE164', () {
    expect(ContactPhoneHelpers.isValidE164('+919876543210'), isTrue);
    expect(ContactPhoneHelpers.isValidE164('9876543210'), isFalse);
  });
}
