/// DNP DS-RX1 print dimensions (matches native [DnpPrintSize.kt]).
class DnpPrintSize {
  const DnpPrintSize({
    required this.usbLabel,
    required this.wifiPrintSize,
  });

  final String usbLabel;
  final String wifiPrintSize;

  static const portrait4x6 = DnpPrintSize(usbLabel: '4x6', wifiPrintSize: 's4x6');
  static const landscape6x4 = DnpPrintSize(usbLabel: '4x6', wifiPrintSize: 's6x4');
  static const strip2x6 = DnpPrintSize(usbLabel: '2x6', wifiPrintSize: 's2x6');
  static const size5x7 = DnpPrintSize(usbLabel: '5x7', wifiPrintSize: 's5x7');
  static const size6x8 = DnpPrintSize(usbLabel: '6x8', wifiPrintSize: 's6x8');
  static const stripDual6x2 = DnpPrintSize(usbLabel: '2x6', wifiPrintSize: 's6x2_2');

  /// Maps kiosk network `printSize` tokens to DNP USB paper + Wi-Fi tokens.
  static DnpPrintSize fromNetworkPrintSize(String? raw) {
    final token = raw?.trim().toLowerCase() ?? '';
    return switch (token) {
      's6x4' => landscape6x4,
      's5x7' => size5x7,
      's6x8' => size6x8,
      's2x6' => strip2x6,
      's6x2_2' => stripDual6x2,
      _ => portrait4x6,
    };
  }
}
