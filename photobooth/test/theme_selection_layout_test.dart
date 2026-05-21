import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/theme_selection/theme_selection_layout.dart';
import 'package:photobooth/utils/constants.dart';

void main() {
  test('carouselViewportFraction phone portrait', () {
    expect(
      ThemeSelectionLayoutMetrics.carouselViewportFraction(
        width: 400,
        height: 800,
      ),
      0.76,
    );
  });

  test('gridCrossAxisCount tablet landscape', () {
    expect(
      ThemeSelectionLayoutMetrics.gridCrossAxisCount(
        width: 1300,
        isLandscape: true,
      ),
      5,
    );
  });

  test('resolveThemeImageUrl prefixes relative path', () {
    final url = ThemeSelectionLayoutMetrics.resolveThemeImageUrl('/img/a.jpg');
    expect(url, contains('/img/a.jpg'));
    expect(url, isNot(startsWith('/')));
  });

  test('carousel uses default fraction on wide screens', () {
    expect(
      ThemeSelectionLayoutMetrics.carouselViewportFraction(
        width: 1200,
        height: 800,
      ),
      AppConstants.kThemeCarouselViewportFraction,
    );
  });
}
