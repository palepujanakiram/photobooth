import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/local_receipt_pdf.dart';

void main() {
  test('buildLocalReceiptPdf writes a pdf for zero and positive amounts', () async {
    final zero = await buildLocalReceiptPdf(
      receiptNumber: 'FZ/K1/2627/00001',
      amount: -3,
      paymentMode: 'CASH',
      kioskCode: 'K1',
    );
    expect(zero.length, greaterThan(40));

    final dated = await buildLocalReceiptPdf(
      receiptNumber: 'FZ/K1/2627/00002',
      amount: 10,
      paymentMode: 'UPI',
      kioskCode: 'K1',
      issuedAt: DateTime.utc(2026, 8, 23),
    );
    expect(dated, isNotEmpty);
  });
}
