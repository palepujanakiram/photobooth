/// Tax breakdown matching ZenAI `assembleReceiptPdfInput` / `taxBreakdown`.
class LocalReceiptTaxBreakdown {
  const LocalReceiptTaxBreakdown({
    required this.taxableValue,
    this.cgstRate,
    this.cgstAmount,
    this.sgstRate,
    this.sgstAmount,
    this.igstRate,
    this.igstAmount,
  });

  final double taxableValue;
  final double? cgstRate;
  final double? cgstAmount;
  final double? sgstRate;
  final double? sgstAmount;
  final double? igstRate;
  final double? igstAmount;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'taxableValue': taxableValue,
        if (cgstRate != null) 'cgstRate': cgstRate,
        if (cgstAmount != null) 'cgstAmount': cgstAmount,
        if (sgstRate != null) 'sgstRate': sgstRate,
        if (sgstAmount != null) 'sgstAmount': sgstAmount,
        if (igstRate != null) 'igstRate': igstRate,
        if (igstAmount != null) 'igstAmount': igstAmount,
      };
}

LocalReceiptTaxBreakdown localReceiptTaxBreakdown({
  required int amountRupees,
  required int gstRateBps,
  required String gstSplitMode,
  required bool complimentary,
}) {
  final gross = complimentary ? 0 : (amountRupees < 0 ? 0 : amountRupees);
  if (gross <= 0) {
    return const LocalReceiptTaxBreakdown(taxableValue: 0);
  }
  final rate = (gstRateBps < 0 ? 0 : gstRateBps) / 10000.0;
  if (rate <= 0) {
    return LocalReceiptTaxBreakdown(
      taxableValue: _round2(gross.toDouble()),
    );
  }
  final taxable = gross / (1 + rate);
  final taxableRounded = _round2(taxable);
  final remainder = _round2(gross - taxableRounded);

  if (gstSplitMode == 'igst') {
    return LocalReceiptTaxBreakdown(
      taxableValue: taxableRounded,
      igstRate: rate,
      igstAmount: remainder,
    );
  }

  final half = _round2((taxable * rate) / 2);
  return LocalReceiptTaxBreakdown(
    taxableValue: taxableRounded,
    cgstRate: rate / 2,
    sgstRate: rate / 2,
    cgstAmount: half,
    sgstAmount: _round2(remainder - half),
  );
}

double _round2(double v) => (v * 100).round() / 100.0;
