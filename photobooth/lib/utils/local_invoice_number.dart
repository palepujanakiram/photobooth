/// Kiosk-owned tax invoice numbers: FZ/{booth}/{fy}/{#####}
///
/// Booth is the full sanitized kiosk code so ODEON-01 and ODEON-02 never
/// share a series while offline.
const int kBoothInvoiceCodeMaxLen = 16;

String boothInvoiceCode(String? kioskCode) {
  final raw = (kioskCode == null || kioskCode.trim().isEmpty)
      ? 'GN'
      : kioskCode.trim().toUpperCase();
  final cleaned = raw
      .replaceAll(RegExp(r'[^A-Z0-9-]'), '')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (cleaned.length >= 2) {
    return cleaned.length <= kBoothInvoiceCodeMaxLen
        ? cleaned
        : cleaned.substring(0, kBoothInvoiceCodeMaxLen);
  }
  final alnum = raw.replaceAll(RegExp(r'[^A-Z0-9]'), '');
  final base = alnum.isEmpty ? 'GN' : alnum;
  return base.padRight(2, 'X');
}

/// Indian FY from the device calendar (kiosks run Asia/Kolkata).
String indianFinancialYearCode(DateTime date) {
  final year = date.year;
  final month = date.month;
  final startYear = month >= 4 ? year : year - 1;
  final endYear = startYear + 1;
  final a = (startYear % 100).toString().padLeft(2, '0');
  final b = (endYear % 100).toString().padLeft(2, '0');
  return '$a$b';
}

String formatInvoiceNumber(String kioskCode, String fyCode, int seq) {
  final booth = boothInvoiceCode(kioskCode);
  final fy = fyCode.replaceAll(RegExp(r'\D'), '');
  final fy4 = fy.length >= 4
      ? fy.substring(0, 4)
      : fy.padLeft(4, '0');
  final n = seq < 1 ? 1 : seq;
  return 'FZ/$booth/$fy4/${n.toString().padLeft(5, '0')}';
}

String receiptSeriesKey(String kioskCode, DateTime date) {
  return '${boothInvoiceCode(kioskCode)}/${indianFinancialYearCode(date)}';
}

final _kioskReceiptNumber = RegExp(
  r'^FZ/[A-Z0-9-]{2,16}/\d{4}/\d{5}$',
);

/// Kiosk-issued tax invoice id. Invalid values are ignored.
String? parseKioskReceiptNumber(String? raw) {
  if (raw == null) return null;
  final n = raw.trim().toUpperCase();
  if (!_kioskReceiptNumber.hasMatch(n)) return null;
  return n;
}
