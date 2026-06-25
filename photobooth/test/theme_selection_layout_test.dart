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
      0.92,
    );
  });

  test('carouselViewportFraction single theme uses full width', () {
    expect(
      ThemeSelectionLayoutMetrics.carouselViewportFraction(
        width: 400,
        height: 800,
        themeCount: 1,
      ),
      1.0,
    );
  });

  test('pickerCardSize fills portrait slot', () {
    final size = ThemeSelectionLayoutMetrics.pickerCardSize(
      maxWidth: 360,
      maxHeight: 520,
      aspect: 3 / 4.5,
    );
    expect(size.height, closeTo(520, 0.01));
    expect(size.width, closeTo(346.67, 0.1));
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
