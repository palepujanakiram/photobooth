import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/receipt_merchant_cache.dart';
import 'package:photobooth/services/receipt/local_receipt_escpos.dart';
import 'package:photobooth/services/receipt/local_receipt_slip.dart';
import 'package:photobooth/services/receipt/local_receipt_tax.dart';

void main() {
  test('tax breakdown matches inclusive 18% CGST/SGST', () {
    final tax = localReceiptTaxBreakdown(
      amountRupees: 250,
      gstRateBps: 1800,
      gstSplitMode: 'cgst_sgst',
      complimentary: false,
    );
    expect(tax.taxableValue, 211.86);
    expect(tax.cgstAmount, isNotNull);
    expect(tax.sgstAmount, isNotNull);
    expect(
      ((tax.cgstAmount! + tax.sgstAmount!) * 100).round() / 100,
      closeTo(38.14, 0.01),
    );
  });

  test('igst mode uses single tax line', () {
    final tax = localReceiptTaxBreakdown(
      amountRupees: 118,
      gstRateBps: 1800,
      gstSplitMode: 'igst',
      complimentary: false,
    );
    expect(tax.igstAmount, isNotNull);
    expect(tax.cgstAmount, isNull);
  });

  test('slip lines include GSTIN and invoice number', () {
    final merchant = ReceiptMerchantCache(
      legalName: 'Sri Sarani Ventures Private Limited',
      cin: 'U12345',
      gstin: '36AAAAA0000A1Z5',
      venueName: 'Test Mall',
      placeOfSupply: 'Telangana (36)',
      gstRateBps: 1800,
      hsnSac: '998383',
      kioskCode: 'ODEON-01',
    );
    final tax = localReceiptTaxBreakdown(
      amountRupees: 250,
      gstRateBps: 1800,
      gstSplitMode: 'cgst_sgst',
      complimentary: false,
    );
    final lines = buildLocalReceiptSlipLines(
      LocalReceiptSlipInput(
        receiptNumber: 'FZ/ODEON-01/2627/00001',
        amount: 250,
        paymentMode: 'CASH',
        merchant: merchant,
        tax: tax,
        issuedAt: DateTime.utc(2026, 8, 25, 12),
      ),
    );
    final text = lines.join('|');
    expect(text, contains('TAX INVOICE'));
    expect(text, contains('GSTIN: 36AAAAA0000A1Z5'));
    expect(text, contains('Invoice No:'));
    expect(text, contains('FZ/ODEON-01/2627/000'));
    expect(text, contains('CGST'));
    expect(text, contains('TOTAL (incl. GST)'));
  });

  test('escpos payload is non-empty and starts with init', () {
    final merchant = const ReceiptMerchantCache(
      displayName: 'FotoZen.AI',
      gstin: '36AAAAA0000A1Z5',
      gstRateBps: 1800,
      kioskCode: 'K1',
    );
    final tax = localReceiptTaxBreakdown(
      amountRupees: 100,
      gstRateBps: 1800,
      gstSplitMode: 'cgst_sgst',
      complimentary: false,
    );
    final bytes = buildLocalReceiptEscPos(
      LocalReceiptSlipInput(
        receiptNumber: 'FZ/K1/2627/00002',
        amount: 100,
        paymentMode: 'CASH',
        merchant: merchant,
        tax: tax,
        issuedAt: DateTime.utc(2026, 8, 25),
      ),
    );
    expect(bytes.length, greaterThan(40));
    expect(bytes[0], 0x1b);
    expect(bytes[1], 0x40);
  });
}
