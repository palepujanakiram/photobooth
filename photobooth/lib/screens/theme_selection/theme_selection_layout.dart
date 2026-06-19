import '../../utils/app_config.dart';
import '../../utils/constants.dart';

/// Responsive layout helpers for [ThemeSelectionScreen] (carousel + card grid).
class ThemeSelectionLayoutMetrics {
  const ThemeSelectionLayoutMetrics._();

  /// Hero carousel [PageController.viewportFraction] by screen size.
  ///
  /// Uses nearly full width on phones; [themeCount] of 1 skips side-peek padding.
  static double carouselViewportFraction({
    required double width,
    required double height,
    int themeCount = 0,
  }) {
    if (themeCount == 1) return 1.0;
    if (width < AppConstants.kTabletBreakpoint) {
      return height >= width ? 0.92 : 0.82;
    }
    if (width < 900) return 0.58;
    return AppConstants.kThemeCarouselViewportFraction;
  }

  /// Fills the carousel slot while preserving [aspect] (width / height).
  static ({double width, double height}) pickerCardSize({
    required double maxWidth,
    required double maxHeight,
    required double aspect,
  }) {
    if (maxWidth <= 0 || maxHeight <= 0) {
      return (width: 0.0, height: 0.0);
    }
    final safeAspect = aspect.clamp(0.35, 2.85);
    late double cardW;
    late double cardH;
    if (maxWidth / maxHeight > safeAspect) {
      cardH = maxHeight;
      cardW = cardH * safeAspect;
    } else {
      cardW = maxWidth;
      cardH = cardW / safeAspect;
    }
    return (width: cardW, height: cardH);
  }

  /// Grid column count for card-grid theme picker.
  static int gridCrossAxisCount({
    required double width,
    required bool isLandscape,
  }) {
    if (width >= 1200) return isLandscape ? 5 : 4;
    if (width >= 900) return 4;
    if (width >= 700) return 3;
    return 2;
  }

  /// Resolves theme sample image URL like [ThemeCard] / slideshow.
  static String resolveThemeImageUrl(String imageUrl) {
    final trimmed = imageUrl.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    final base = AppConfig.baseUrl.endsWith('/')
        ? AppConfig.baseUrl.substring(0, AppConfig.baseUrl.length - 1)
        : AppConfig.baseUrl;
    final path = trimmed.startsWith('/') ? trimmed : '/$trimmed';
    return '$base$path';
  }
}
