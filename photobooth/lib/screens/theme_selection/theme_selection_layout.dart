import '../../utils/app_config.dart';
import '../../utils/constants.dart';

/// Responsive layout helpers for [ThemeSelectionScreen] (carousel + card grid).
class ThemeSelectionLayoutMetrics {
  const ThemeSelectionLayoutMetrics._();

  /// Hero carousel [PageController.viewportFraction] by screen size.
  static double carouselViewportFraction({
    required double width,
    required double height,
  }) {
    if (width < AppConstants.kTabletBreakpoint) {
      return height >= width ? 0.76 : 0.52;
    }
    if (width < 900) return 0.42;
    return AppConstants.kThemeCarouselViewportFraction;
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
