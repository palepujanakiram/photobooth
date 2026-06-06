import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/terms_and_conditions/terms_layout_metrics.dart';

void main() {
  test('cardMaxWidth uses fixed cap on wide screens', () {
    const layout = TermsLayoutMetrics(screenWidth: 800, isLandscape: false);
    expect(layout.cardMaxWidth, 500);
  });

  test('compact padding is smaller than normal', () {
    const layout = TermsLayoutMetrics(screenWidth: 400, isLandscape: true);
    expect(
      layout.cardPadding(compact: true),
      lessThan(layout.cardPadding(compact: false)),
    );
  });
}
