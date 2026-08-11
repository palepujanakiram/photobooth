import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/splash/app_splash_input_helpers.dart';

void main() {
  group('splashShouldBlockWithBusyOverlay', () {
    test('blocks only while busy and form is hidden', () {
      expect(
        splashShouldBlockWithBusyOverlay(busy: true, showForm: false),
        isTrue,
      );
      expect(
        splashShouldBlockWithBusyOverlay(busy: true, showForm: true),
        isFalse,
      );
      expect(
        splashShouldBlockWithBusyOverlay(busy: false, showForm: false),
        isFalse,
      );
    });
  });

  group('splashCodeFieldEnabled', () {
    test('stays enabled whenever the entry form is shown', () {
      expect(
        splashCodeFieldEnabled(busy: true, showForm: true),
        isTrue,
      );
      expect(
        splashCodeFieldEnabled(busy: false, showForm: true),
        isTrue,
      );
      expect(
        splashCodeFieldEnabled(busy: true, showForm: false),
        isFalse,
      );
    });
  });
}
