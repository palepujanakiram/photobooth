import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/theme_slideshow/theme_slideshow_layout.dart';

void main() {
  test('selectSlideshowDisplayUrls prefers preloaded list', () {
    expect(
      selectSlideshowDisplayUrls(
        sampleUrls: ['a', 'b'],
        preloadedUrls: ['x'],
      ),
      ['x'],
    );
    expect(
      selectSlideshowDisplayUrls(
        sampleUrls: ['a', 'b'],
        preloadedUrls: [],
      ),
      ['a', 'b'],
    );
  });

  test('SlideshowLayoutMetrics portrait phone padding', () {
    const metrics = SlideshowLayoutMetrics(
      isLandscape: false,
      isTablet: false,
    );
    expect(metrics.edgePaddingLeft, 20.0);
    expect(metrics.brandTitleSize, 24.0);
  });
}
