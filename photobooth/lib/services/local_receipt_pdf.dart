import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;

import '../models/receipt_merchant_cache.dart';
import 'receipt/local_receipt_assemble.dart';
import 'receipt/local_receipt_slip.dart';
import 'local_kiosk_settlement.dart';

/// On-device tax invoice PDF using the same slip lines as thermal ESC/POS.
Future<Uint8List> buildLocalReceiptPdf({
  required String receiptNumber,
  required int amount,
  required String paymentMode,
  required String kioskCode,
  DateTime? issuedAt,
  ReceiptMerchantCache? merchant,
  int quantity = 1,
  String? themeName,
  String? customerName,
  String? customerPhone,
  String? shareUrl,
}) async {
  final at = issuedAt ?? DateTime.now();
  final rupees = amount < 0 ? 0 : amount;
  final base = merchant ?? const ReceiptMerchantCache(displayName: 'FotoZen.AI');
  final cache = (base.kioskCode == null || base.kioskCode!.trim().isEmpty) &&
          kioskCode.trim().isNotEmpty
      ? ReceiptMerchantCache(
          legalName: base.legalName,
          displayName: base.displayName,
          cin: base.cin,
          gstin: base.gstin,
          venueName: base.venueName,
          placeOfSupply: base.placeOfSupply,
          address: base.address,
          phone: base.phone,
          email: base.email,
          notes: base.notes,
          gstRateBps: base.gstRateBps,
          gstSplitMode: base.gstSplitMode,
          hsnSac: base.hsnSac,
          productName: base.productName,
          kioskName: base.kioskName,
          kioskCode: kioskCode,
        )
      : base;
  final issue = LocalReceiptIssue(
    id: 'local-pdf',
    receiptNumber: receiptNumber,
    json: <String, dynamic>{
      'amount': rupees,
      'paymentMode': paymentMode,
      'issuedAt': at.toIso8601String(),
    },
  );
  final slip = assembleLocalReceiptSlip(
    receipt: issue,
    merchant: cache,
    quantity: quantity,
    themeName: themeName,
    customerName: customerName,
    customerPhone: customerPhone,
    shareUrl: shareUrl,
  );
  final lines = buildLocalReceiptSlipLines(slip)
      .where((l) => l != kLocalReceiptSlipQrPlaceholder)
      .toList();

  final doc = pw.Document();
  doc.addPage(
    pw.Page(
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          for (final line in lines) pw.Text(line),
        ],
      ),
    ),
  );
  return doc.save();
}
