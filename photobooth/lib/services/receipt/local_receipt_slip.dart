import '../../models/receipt_merchant_cache.dart';
import 'local_receipt_tax.dart';

const kLocalReceiptSlipQrPlaceholder = '__QR__';
const kLocalReceiptThermalChars = 32;
const kLocalReceiptLinkTtlHours = 7 * 24;

/// Input for thermal slip lines (parity with ZenAI ReceiptPdfInput subset).
class LocalReceiptSlipInput {
  const LocalReceiptSlipInput({
    required this.receiptNumber,
    required this.amount,
    required this.paymentMode,
    required this.merchant,
    required this.tax,
    required this.issuedAt,
    this.currency = 'INR',
    this.themeName,
    this.quantity = 1,
    this.customerName,
    this.customerPhone,
    this.shareUrl,
    this.transactionRef,
  });

  final String receiptNumber;
  final int amount;
  final String paymentMode;
  final ReceiptMerchantCache merchant;
  final LocalReceiptTaxBreakdown tax;
  final DateTime issuedAt;
  final String currency;
  final String? themeName;
  final int quantity;
  final String? customerName;
  final String? customerPhone;
  final String? shareUrl;
  final String? transactionRef;
}

List<String> wrapThermalLine(String text, [int width = kLocalReceiptThermalChars]) {
  final raw = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (raw.isEmpty) return const [];
  final out = <String>[];
  var rest = raw;
  while (rest.length > width) {
    var breakAt = rest.lastIndexOf(' ', width);
    if (breakAt < (width / 2).floor()) breakAt = width;
    out.add(rest.substring(0, breakAt).trimRight());
    rest = rest.substring(breakAt).trimLeft();
  }
  if (rest.isNotEmpty) out.add(rest);
  return out;
}

List<String> wrapMerchantNameLines(
  String name, [
  int width = kLocalReceiptThermalChars,
]) {
  final raw = name.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (raw.isEmpty) return const [];
  if (raw.length <= width) return [raw];

  final suffixMatch = RegExp(
    r'\s+((?:Private\s+Limited|Pvt\.?\s*Ltd\.?|Limited|Ltd\.?))$',
    caseSensitive: false,
  ).firstMatch(raw);
  if (suffixMatch != null) {
    final head = raw.substring(0, suffixMatch.start).trimRight();
    final suffix = suffixMatch.group(1)!.trim();
    if (head.isNotEmpty &&
        head.length <= width &&
        suffix.length <= width &&
        head.length + 1 + suffix.length > width) {
      return [head, suffix];
    }
  }
  return wrapThermalLine(raw, width);
}

/// Plain text lines matching ZenAI `buildReceiptSlipLines`.
List<String> buildLocalReceiptSlipLines(LocalReceiptSlipInput input) {
  final lines = <String>[];
  final m = input.merchant;
  const title = 'TAX INVOICE';

  lines.addAll(wrapMerchantNameLines(m.merchantName));
  _pushWrapped(lines, title);
  if (m.hasGstin) {
    _pushWrapped(lines, 'Original for Recipient');
  }
  final cin = m.cin?.trim() ?? '';
  if (cin.isNotEmpty) _pushWrapped(lines, 'CIN: $cin');
  final venue = m.venueName?.trim() ?? '';
  if (venue.isNotEmpty) _pushWrapped(lines, venue);
  for (final a in _addressLines(m.address)) {
    _pushWrapped(lines, a);
  }
  final gstin = m.gstin?.trim() ?? '';
  if (gstin.isNotEmpty) _pushWrapped(lines, 'GSTIN: $gstin');
  final pos = m.placeOfSupply?.trim() ?? '';
  if (pos.isNotEmpty) _pushWrapped(lines, 'Place of Supply: $pos');
  final contact = [m.phone, m.email]
      .where((e) => (e?.trim() ?? '').isNotEmpty)
      .map((e) => e!.trim())
      .join(' / ');
  if (contact.isNotEmpty) _pushWrapped(lines, contact);
  final booth = (m.kioskCode?.trim().isNotEmpty == true)
      ? m.kioskCode!.trim()
      : (m.kioskName?.trim() ?? '');
  if (booth.isNotEmpty) _pushWrapped(lines, 'Booth ID: $booth');

  lines.add('-' * kLocalReceiptThermalChars);
  _pushWrapped(lines, 'Invoice No: ${input.receiptNumber}');
  _pushWrapped(lines, 'Date: ${_formatDateTime(input.issuedAt)}');
  _pushWrapped(lines, 'Recipient: Unregistered (B2C)');

  final theme = input.themeName?.trim() ?? '';
  final item = theme.isEmpty
      ? m.productName
      : '${m.productName} - $theme';
  _pushWrapped(lines, 'Item: $item');
  final qty = input.quantity < 1 ? 1 : input.quantity;
  final hsn = m.hsnSac.trim();
  if (hsn.isNotEmpty) {
    _pushWrapped(lines, 'SAC: $hsn  Qty: $qty');
  } else if (qty > 1) {
    _pushWrapped(lines, 'Qty: $qty');
  }

  final guest = input.customerName?.trim() ?? '';
  if (guest.isNotEmpty) _pushWrapped(lines, 'Guest: $guest');
  final phone = input.customerPhone?.trim() ?? '';
  if (phone.isNotEmpty) _pushWrapped(lines, 'Phone: $phone');

  lines.add('-' * kLocalReceiptThermalChars);

  final tax = input.tax;
  final hasTax = tax.igstAmount != null ||
      (tax.cgstAmount != null && tax.sgstAmount != null);
  if (hasTax) {
    _pushWrapped(
      lines,
      'Taxable Value: ${_money2(tax.taxableValue, input.currency)}',
    );
    if (tax.igstAmount != null) {
      final label = tax.igstRate != null
          ? 'IGST @ ${(tax.igstRate! * 100).toStringAsFixed(0)}%'
          : 'IGST';
      _pushWrapped(lines, '$label: ${_money2(tax.igstAmount!, input.currency)}');
    } else {
      final cLabel = tax.cgstRate != null
          ? 'CGST @ ${(tax.cgstRate! * 100).toStringAsFixed(0)}%'
          : 'CGST';
      final sLabel = tax.sgstRate != null
          ? 'SGST @ ${(tax.sgstRate! * 100).toStringAsFixed(0)}%'
          : 'SGST';
      _pushWrapped(
        lines,
        '$cLabel: ${_money2(tax.cgstAmount!, input.currency)}',
      );
      _pushWrapped(
        lines,
        '$sLabel: ${_money2(tax.sgstAmount!, input.currency)}',
      );
    }
  }

  _pushWrapped(
    lines,
    'TOTAL (incl. GST): ${_money(input.amount.toDouble(), input.currency)}',
  );
  _pushWrapped(lines, 'Payment: ${input.paymentMode}');
  if (input.paymentMode == 'UPI') {
    final ref = input.transactionRef?.trim() ?? '';
    if (ref.isNotEmpty) {
      _pushWrapped(lines, 'UPI Ref: ${_maskTxnRef(ref)}');
    }
  }
  final status =
      input.paymentMode == 'COMPLIMENTARY' ? 'COMPLIMENTARY' : 'PAID';
  _pushWrapped(lines, 'Status: $status');

  lines.add('-' * kLocalReceiptThermalChars);
  lines.add('Thank you! Tag us @fotozenai');
  lines.add('fotozenai.com');

  final share = input.shareUrl?.trim() ?? '';
  if (share.isNotEmpty) {
    lines.add('Scan to download your photo');
    lines.add(kLocalReceiptSlipQrPlaceholder);
    final days = (kLocalReceiptLinkTtlHours / 24).round().clamp(1, 365);
    lines.add('Valid for $days days');
  }

  final note = m.notes?.trim() ?? '';
  if (note.isNotEmpty) _pushWrapped(lines, note);

  lines.add('Computer-generated invoice.');
  lines.add('No signature required.');
  return lines;
}

void _pushWrapped(List<String> out, String text) {
  out.addAll(wrapThermalLine(text));
}

List<String> _addressLines(ReceiptMerchantAddress? addr) {
  if (addr == null) return const [];
  final lines = <String>[];
  final l1 = addr.line1?.trim() ?? '';
  if (l1.isNotEmpty) lines.add(l1);
  final l2 = addr.line2?.trim() ?? '';
  if (l2.isNotEmpty) lines.add(l2);
  final cityState = [addr.city, addr.state]
      .where((e) => (e?.trim() ?? '').isNotEmpty)
      .map((e) => e!.trim())
      .join(', ');
  final cityLine = [cityState, addr.postalCode]
      .where((e) => (e?.trim() ?? '').isNotEmpty)
      .map((e) => e!.trim())
      .join(' - ');
  if (cityLine.isNotEmpty) lines.add(cityLine);
  final country = addr.country?.trim() ?? '';
  if (country.isNotEmpty) lines.add(country);
  return lines;
}

String _money(double amount, String currency) {
  if (currency == 'INR') {
    return 'Rs.${amount.toStringAsFixed(0)}';
  }
  return '$currency ${amount.toStringAsFixed(0)}';
}

String _money2(double amount, String currency) {
  if (currency == 'INR') {
    return 'Rs.${amount.toStringAsFixed(2)}';
  }
  return '$currency ${amount.toStringAsFixed(2)}';
}

String _formatDateTime(DateTime d) {
  // Stable Asia/Kolkata-ish local formatting without intl dependency.
  final local = d.toLocal();
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final day = local.day.toString().padLeft(2, '0');
  final mon = months[local.month - 1];
  final year = local.year;
  var hour = local.hour % 12;
  if (hour == 0) hour = 12;
  final min = local.minute.toString().padLeft(2, '0');
  final ampm = local.hour >= 12 ? 'pm' : 'am';
  return '$day $mon $year, ${hour.toString().padLeft(2, '0')}:$min $ampm';
}

String _maskTxnRef(String ref) {
  final s = ref.trim();
  if (s.length <= 8) return s;
  return '${s.substring(0, 4)}XXXX${s.substring(s.length - 4)}';
}
