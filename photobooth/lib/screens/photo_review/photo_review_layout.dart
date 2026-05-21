/// Responsive layout tokens for [PhotoReviewScreen].
///
/// Landscape uses tighter padding and smaller type so the two-column review
/// fits on tablets and phones without scrolling the action buttons off-screen.
class ReviewLayoutMetrics {
  const ReviewLayoutMetrics({required this.isLandscape});

  final bool isLandscape;

  /// Outer padding around the review body.
  double get contentPadding => isLandscape ? 10.0 : 16.0;

  /// “Your photo” / section labels.
  double get labelFontSize => isLandscape ? 14.0 : 18.0;

  double get labelGap => isLandscape ? 6.0 : 12.0;
  double get columnGap => isLandscape ? 10.0 : 16.0;
  double get sectionGap => isLandscape ? 8.0 : 16.0;

  /// Bottom padding for primary actions, including [safeBottom] inset.
  double bottomButtonPadding(double safeBottom) =>
      (isLandscape ? 10.0 : 16.0) + safeBottom;
}
