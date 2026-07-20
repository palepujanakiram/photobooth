import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/utils/platform_capabilities.dart';

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  void expectMobileFlags(bool expectedMobile) {
    expect(isMobileNativePlatform, expectedMobile);
    expect(supportsLiveCameraPreview, expectedMobile);
    expect(supportsTermsCameraPriming, expectedMobile);
    expect(supportsFirebaseMessaging, expectedMobile);
    expect(supportsBugsnagNative, expectedMobile);
    expect(supportsEmbeddedWebView, expectedMobile);
    expect(isDesktopPlatform, isFalse);
    expect(usesDesktopPhotoPicker, isFalse);
  }

  void expectDesktopFlags() {
    expect(isDesktopPlatform, isTrue);
    expect(usesDesktopPhotoPicker, isTrue);
    expect(isMobileNativePlatform, isFalse);
    expect(supportsFirebaseMessaging, isFalse);
    expect(supportsEmbeddedWebView, isFalse);
    expect(supportsLiveCameraPreview, isFalse);
    expect(supportsTermsCameraPriming, isFalse);
    expect(supportsBugsnagNative, isFalse);
  }

  test('android flags', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expectMobileFlags(true);
  });

  test('ios flags', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expectMobileFlags(true);
  });

  test('windows desktop flags', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expectDesktopFlags();
  });

  test('macOS desktop flags', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expectDesktopFlags();
  });

  test('linux desktop flags', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expectDesktopFlags();
  });

  test('fuchsia is neither mobile nor desktop', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.fuchsia;
    expect(isMobileNativePlatform, isFalse);
    expect(isDesktopPlatform, isFalse);
    expect(usesDesktopPhotoPicker, isFalse);
    expect(supportsLiveCameraPreview, isFalse);
    expect(supportsEmbeddedWebView, isFalse);
    expect(supportsFirebaseMessaging, isFalse);
  });
}
