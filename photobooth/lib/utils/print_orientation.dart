import '../utils/constants.dart';

/// Customer-facing print layout (4×6 portrait vs 6×4 landscape).
enum PrintOrientation {
  portrait,
  landscape;

  /// Solo and couples → portrait; groups of 3+ → landscape (matches server framing).
  static PrintOrientation fromPersonCount(int? personCount) {
    final count = personCount != null && personCount > 0 ? personCount : 1;
    return count <= 2 ? PrintOrientation.portrait : PrintOrientation.landscape;
  }

  static PrintOrientation? tryParse(String? raw) {
    if (raw == null) return null;
    switch (raw.trim().toLowerCase()) {
      case 'portrait':
      case 'p':
        return PrintOrientation.portrait;
      case 'landscape':
      case 'l':
        return PrintOrientation.landscape;
      default:
        return null;
    }
  }

  String get apiValue => name;

  /// Width ÷ height for hero/preview cards.
  double get cardAspectRatio => switch (this) {
        PrintOrientation.portrait => AppConstants.kThemeSelectedCardAspectRatio,
        PrintOrientation.landscape =>
          AppConstants.kBeholdSingleResultDefaultAspectRatio,
      };

  /// Network printer `printSize` token (DNP / kiosk API).
  String get printSize => switch (this) {
        PrintOrientation.portrait => AppConstants.kPrintSizePortrait4x6,
        PrintOrientation.landscape => AppConstants.kPrintSizeLandscape6x4,
      };

  String get label => switch (this) {
        PrintOrientation.portrait => 'Portrait',
        PrintOrientation.landscape => 'Landscape',
      };
}
