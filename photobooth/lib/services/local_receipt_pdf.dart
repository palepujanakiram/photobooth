import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;

/// Minimal on-device tax invoice. Fly still owns the branded GST PDF after sync.
Future<Uint8List> buildLocalReceiptPdf({
  required String receiptNumber,
  required int amount,
  required String paymentMode,
  required String kioskCode,
  DateTime? issuedAt,
}) async {
  final at = issuedAt ?? DateTime.now();
  final rupees = amount < 0 ? 0 : amount;
  final doc = pw.Document();
  doc.addPage(
    pw.Page(
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('TAX INVOICE'),
          pw.SizedBox(height: 12),
          pw.Text('FotoZen.AI'),
          pw.Text('Invoice: $receiptNumber'),
          pw.Text('Kiosk: $kioskCode'),
          pw.Text('Date: ${at.toIso8601String()}'),
          pw.Text('Mode: $paymentMode'),
          pw.Text('Amount: INR $rupees'),
        ],
      ),
    ),
  );
  return doc.save();
}
