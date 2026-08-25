import '../../models/receipt_merchant_cache.dart';
import '../local_kiosk_settlement.dart';
import 'local_receipt_slip.dart';
import 'local_receipt_tax.dart';

/// Builds the same GST slip input used for local ESC/POS + PDF.
LocalReceiptSlipInput assembleLocalReceiptSlip({
  required LocalReceiptIssue receipt,
  required ReceiptMerchantCache merchant,
  int quantity = 1,
  String? themeName,
  String? customerName,
  String? customerPhone,
  String? shareUrl,
  String? transactionRef,
}) {
  final amount = _amountFromReceipt(receipt);
  final mode = (receipt.json['paymentMode']?.toString() ?? 'CASH').trim();
  final complimentary = mode == 'COMPLIMENTARY';
  final tax = localReceiptTaxBreakdown(
    amountRupees: amount,
    gstRateBps: merchant.gstRateBps,
    gstSplitMode: merchant.gstSplitMode,
    complimentary: complimentary,
  );
  final issuedRaw = receipt.json['issuedAt']?.toString();
  final issuedAt = DateTime.tryParse(issuedRaw ?? '') ?? DateTime.now();
  return LocalReceiptSlipInput(
    receiptNumber: receipt.receiptNumber,
    amount: complimentary ? 0 : amount,
    paymentMode: mode.isEmpty ? 'CASH' : mode,
    merchant: merchant,
    tax: tax,
    issuedAt: issuedAt,
    themeName: themeName,
    quantity: quantity < 1 ? 1 : quantity,
    customerName: customerName,
    customerPhone: customerPhone,
    shareUrl: shareUrl,
    transactionRef: transactionRef,
  );
}

int _amountFromReceipt(LocalReceiptIssue receipt) {
  final raw = receipt.json['amount'];
  if (raw is int) return raw < 0 ? 0 : raw;
  if (raw is num) return raw < 0 ? 0 : raw.round();
  return int.tryParse(raw?.toString() ?? '')?.clamp(0, 1 << 30) ?? 0;
}
