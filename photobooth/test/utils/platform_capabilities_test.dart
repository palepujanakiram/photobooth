import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/utils/platform_capabilities.dart';

void main() {
  test('mobile native excludes web and desktop flags', () {
    // Test VM defaults to android or other; flags are mutually consistent.
    if (isMobileNativePlatform) {
      expect(isDesktopPlatform, isFalse);
      expect(usesDesktopPhotoPicker, isFalse);
      expect(supportsLiveCameraPreview, isTrue);
    }
    if (isDesktopPlatform) {
      expect(isMobileNativePlatform, isFalse);
      expect(usesDesktopPhotoPicker, isTrue);
      expect(supportsFirebaseMessaging, isFalse);
      expect(supportsEmbeddedWebView, isFalse);
    }
  });
}
