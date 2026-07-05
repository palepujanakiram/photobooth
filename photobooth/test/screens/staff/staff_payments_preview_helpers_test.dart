import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/staff/staff_payments_preview_helpers.dart';

void main() {
  test('staffPaymentLoadImageBytes decodes data URLs', () async {
    final bytes = await staffPaymentLoadImageBytes(
      imageUrl: 'data:image/png;base64,YWJj',
    );
    expect(bytes, isNotNull);
    expect(String.fromCharCodes(bytes!), 'abc');
  });

  test('staffPaymentLoadImageBytes returns null for empty url', () async {
    expect(
      await staffPaymentLoadImageBytes(imageUrl: '  '),
      isNull,
    );
  });
}
