import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/receipt/receipt_printer_profile.dart';

void main() {
  group('receiptPrintReceiptQueryParams', () {
    test('includes 80mm defaults', () {
      final params = receiptPrintReceiptQueryParams();
      expect(params['paperWidthMm'], '80');
      expect(params['printWidthDots'], '576');
    });

    test('includes transport when provided', () {
      final params = receiptPrintReceiptQueryParams(transport: 'usb');
      expect(params['transport'], 'usb');
    });
  });
}
