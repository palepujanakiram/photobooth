/// Responsive layout tokens for [ThemeSlideshowScreen].
///
/// Replaces nested ternaries for padding and font sizes. Values match the
/// previous inline layout (portrait phone, portrait tablet, landscape).
class SlideshowLayoutMetrics {
  const SlideshowLayoutMetrics({
    required this.isLandscape,
    required this.isTablet,
  });

  final bool isLandscape;
  final bool isTablet;

  /// Left inset for the theme name overlay above the safe area.
  double get edgePaddingLeft {
    if (isLandscape) return 12.0;
    if (isTablet) return 32.0;
    return 20.0;
  }

  /// Bottom inset for the theme name overlay.
  double get edgePaddingBottom {
    if (isLandscape) return 12.0;
    if (isTablet) return 40.0;
    return 24.0;
  }

  /// Horizontal padding inside the “Touch anywhere to start” card.
  double get overlayPaddingH {
    if (isLandscape) return 20.0;
    if (isTablet) return 48.0;
    return 32.0;
  }

  /// Vertical padding inside the brand overlay card.
  double get overlayPaddingV {
    if (isLandscape) return 16.0;
    if (isTablet) return 32.0;
    return 24.0;
  }

  double get overlayBorderRadius {
    if (isLandscape) return 10.0;
    if (isTablet) return 16.0;
    return 12.0;
  }

  double get brandTitleSize {
    if (isLandscape) return 20.0;
    if (isTablet) return 28.0;
    return 24.0;
  }

  double get brandSubtitleSize {
    if (isLandscape) return 14.0;
    if (isTablet) return 18.0;
    return 16.0;
  }

  double get brandTitleGap {
    if (isLandscape) return 6.0;
    if (isTablet) return 12.0;
    return 8.0;
  }

  double get themeTitleSize {
    if (isLandscape) return 22.0;
    if (isTablet) return 32.0;
    return 28.0;
  }

  double get themeDescSize {
    if (isLandscape) return 14.0;
    if (isTablet) return 18.0;
    return 16.0;
  }

  double get themeDescGap {
    if (isLandscape) return 4.0;
    if (isTablet) return 8.0;
    return 4.0;
  }
}

/// Picks which image URLs the slideshow should display.
///
/// Preloaded URLs are preferred once [ThemeSlideshowViewModel.preloadImages]
/// has finished at least the first frame; otherwise all sample URLs are used.
List<String> selectSlideshowDisplayUrls({
  required List<String> sampleUrls,
  required List<String> preloadedUrls,
}) {
  if (preloadedUrls.isNotEmpty) return preloadedUrls;
  return sampleUrls;
}
