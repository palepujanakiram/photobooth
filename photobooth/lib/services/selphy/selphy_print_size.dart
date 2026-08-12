/// Maps kiosk network `printSize` tokens to Canon Selphy paper cassette labels.
class SelphyPrintSize {
  const SelphyPrintSize(this.paperSize);

  /// Native SDK labels: `4x6` (Post), `L-size`, `Card`.
  final String paperSize;

  static const postcard4x6 = SelphyPrintSize('4x6');
  static const lSize = SelphyPrintSize('L-size');
  static const card = SelphyPrintSize('Card');

  /// CP1500 booth prints are postcard 4×6; exotic DNP strip tokens fall back.
  static SelphyPrintSize fromNetworkPrintSize(String? raw) {
    final token = raw?.trim().toLowerCase() ?? '';
    return switch (token) {
      'l-size' || 'lsize' || 'sl' => lSize,
      'card' || 'scard' => card,
      _ => postcard4x6,
    };
  }
}
