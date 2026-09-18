/// Print raster dimensions, mirroring `DnpPrintSize.kt`.
///
/// The compositor needs the target canvas in Dart to reason about a frame's
/// aspect ratio before handing work to the platform. Values are the DS-RX1 /
/// DS-RX1HS rasters at 300 dpi and must stay in step with the Kotlin enum —
/// they are the printer's, not ours to choose.
class EventPrintSize {
  const EventPrintSize({
    required this.token,
    required this.label,
    required this.width,
    required this.height,
  });

  /// Kiosk / WCM token, e.g. `s4x6`.
  final String token;

  final String label;

  /// Native raster width at 300 dpi. 1920 for every DS-RX1 size.
  final int width;

  final int height;

  double get aspectRatio => width / height;

  /// DS-RX1 native width at 300 dpi.
  static const int nativeWidth = 1920;

  static const size4x6 = EventPrintSize(
    token: 's4x6',
    label: '4x6',
    width: nativeWidth,
    height: 1240,
  );
  static const size5x7 = EventPrintSize(
    token: 's5x7',
    label: '5x7',
    width: nativeWidth,
    height: 2138,
  );
  static const size6x8 = EventPrintSize(
    token: 's6x8',
    label: '6x8',
    width: nativeWidth,
    height: 2436,
  );

  /// 2-inch strip cut on loaded 4×6 media — same raster as 4×6.
  static const size2x6 = EventPrintSize(
    token: 's2x6',
    label: '2x6',
    width: nativeWidth,
    height: 1240,
  );

  static const List<EventPrintSize> all = <EventPrintSize>[
    size4x6,
    size5x7,
    size6x8,
    size2x6,
  ];

  /// Resolves a kiosk token, defaulting to 4×6 like the Kotlin side does.
  ///
  /// `s6x4` and `s6x2_2` are accepted because the backend uses both spellings.
  static EventPrintSize fromToken(String? raw) {
    final token = raw?.trim().toLowerCase() ?? '';
    switch (token) {
      case 's6x4':
      case 's4x6':
        return size4x6;
      case 's5x7':
        return size5x7;
      case 's6x8':
        return size6x8;
      case 's2x6':
      case 's6x2_2':
        return size2x6;
      default:
        return size4x6;
    }
  }
}
