/// Layout tokens for [TermsAndConditionsScreen] (reduces nested ternaries).
class TermsLayoutMetrics {
  const TermsLayoutMetrics({
    required this.screenWidth,
    required this.isLandscape,
  });

  final double screenWidth;
  final bool isLandscape;

  double get cardMaxWidth => screenWidth > 600 ? 500.0 : screenWidth * 0.9;

  double get scrollVerticalPadding => isLandscape ? 8.0 : 16.0;

  double cardPadding({required bool compact}) => compact ? 12.0 : 20.0;

  double sectionGap({required bool compact}) => compact ? 12.0 : 20.0;

  double innerSectionGap({required bool compact}) => compact ? 8.0 : 16.0;

  double checkboxAreaPadding({required bool compact}) => compact ? 12.0 : 16.0;
}
