import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/receipt_merchant_cache.dart';
import 'package:photobooth/services/local_kiosk_settlement.dart';
import 'package:photobooth/services/receipt/local_receipt_assemble.dart';
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

  test('zero GST rate keeps gross as taxable value', () {
    final tax = localReceiptTaxBreakdown(
      amountRupees: 100,
      gstRateBps: 0,
      gstSplitMode: 'cgst_sgst',
      complimentary: false,
    );
    expect(tax.taxableValue, 100);
    expect(tax.cgstAmount, isNull);
  });

  test('assembleLocalReceiptSlip parses num and string amounts', () {
    const merchant = ReceiptMerchantCache(gstRateBps: 0);
    final fromNum = assembleLocalReceiptSlip(
      receipt: const LocalReceiptIssue(
        id: 'r1',
        receiptNumber: 'FZ/1',
        json: {'amount': 12.4, 'paymentMode': 'CASH'},
      ),
      merchant: merchant,
    );
    expect(fromNum.amount, 12);
    final fromString = assembleLocalReceiptSlip(
      receipt: const LocalReceiptIssue(
        id: 'r2',
        receiptNumber: 'FZ/2',
        json: {'amount': '99', 'paymentMode': 'CASH'},
      ),
      merchant: merchant,
    );
    expect(fromString.amount, 99);
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

  test('slip covers address, qty, IGST, UPI, share QR, and non-INR', () {
    expect(wrapMerchantNameLines('Acme Limited'), ['Acme Limited']);
    expect(
      wrapMerchantNameLines('Foo Bar Baz Limited', 10),
      wrapThermalLine('Foo Bar Baz Limited', 10),
    );
    expect(
      wrapThermalLine('ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789ABCD'),
      isNotEmpty,
    );

    final merchant = ReceiptMerchantCache(
      legalName: 'Acme Limited',
      gstin: '36AAAAA0000A1Z5',
      hsnSac: '',
      kioskName: 'Lobby',
      notes: 'Thank you',
      address: const ReceiptMerchantAddress(
        line1: '1 Main St',
        line2: 'Floor 2',
        city: 'Hyderabad',
        state: 'TG',
        postalCode: '500001',
        country: 'IN',
      ),
    );
    const tax = LocalReceiptTaxBreakdown(
      taxableValue: 100,
      igstAmount: 18,
    );
    final lines = buildLocalReceiptSlipLines(
      LocalReceiptSlipInput(
        receiptNumber: 'FZ/K1/1',
        amount: 118,
        paymentMode: 'UPI',
        merchant: merchant,
        tax: tax,
        issuedAt: DateTime(2026, 8, 25),
        currency: 'USD',
        themeName: 'Warm',
        quantity: 2,
        shareUrl: 'https://fotozenai.fly.dev/s/tok',
        transactionRef: 'ABCDEFGHIJKL',
      ),
    );
    final text = lines.join('|');
    expect(text, contains('1 Main St'));
    expect(text, contains('Qty: 2'));
    expect(text, contains('IGST'));
    expect(text, contains('UPI Ref:'));
    expect(text, contains('Scan to download'));
    expect(text, contains('USD '));
    expect(text, contains(kLocalReceiptSlipQrPlaceholder));

    final igstRated = buildLocalReceiptSlipLines(
      LocalReceiptSlipInput(
        receiptNumber: 'FZ/K1/2',
        amount: 118,
        paymentMode: 'CASH',
        merchant: merchant,
        tax: const LocalReceiptTaxBreakdown(
          taxableValue: 100,
          igstRate: 0.18,
          igstAmount: 18,
        ),
        issuedAt: DateTime(2026, 8, 25, 13),
      ),
    );
    expect(igstRated.join('|'), contains('IGST @ 18%'));

    final qr = buildLocalEscPosQrCode('https://fotozenai.fly.dev/s/tok');
    expect(qr, isNotEmpty);
    final withShare = buildLocalReceiptEscPos(
      LocalReceiptSlipInput(
        receiptNumber: 'FZ/K1/1',
        amount: 118,
        paymentMode: 'UPI',
        merchant: merchant,
        tax: tax,
        issuedAt: DateTime(2026, 8, 25),
        shareUrl: 'https://fotozenai.fly.dev/s/tok',
      ),
    );
    expect(withShare.length, greaterThan(qr.length));
  });
}
