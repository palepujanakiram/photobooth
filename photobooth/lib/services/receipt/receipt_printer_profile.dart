/// Posiflow KP 307 UEWB and common 80mm ESC/POS receipt printers.
abstract final class ReceiptPrinterProfile {
  /// Physical paper width (mm).
  static const paperWidthMm = 80;

  /// Printable width at 203 DPI, 8 dots/mm (72mm effective).
  static const printWidthDots = 576;

  /// Bytes per raster row at 8 dots per byte.
  static const printWidthBytes = printWidthDots ~/ 8;
}

/// Query params forwarded to `/api/sessions/:id/print-receipt` so the server
/// can encode raster images for the connected printer.
Map<String, String> receiptPrintReceiptQueryParams({
  int paperWidthMm = ReceiptPrinterProfile.paperWidthMm,
  int printWidthDots = ReceiptPrinterProfile.printWidthDots,
  String? transport,
}) {
  final params = <String, String>{
    'paperWidthMm': '$paperWidthMm',
    'printWidthDots': '$printWidthDots',
  };
  final mode = transport?.trim().toLowerCase();
  if (mode != null && mode.isNotEmpty) {
    params['transport'] = mode;
  }
  return params;
}
