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

  /// Orientation implied by a decoded image's width ÷ height.
  ///
  /// The AI output is the source of truth for framing (groups come back
  /// landscape, solo/couples portrait), so the BEHOLD card can match the real
  /// image instead of a person-count guess that may be stale or wrong.
  static PrintOrientation fromContentAspect(double aspect) {
    return aspect > 1.0
        ? PrintOrientation.landscape
        : PrintOrientation.portrait;
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
