import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/utils/constants.dart';
import 'package:photobooth/utils/network_image_decode.dart';

void main() {
  group('clampNetworkImageDecodePx', () {
    test('clamps below min, above max, and non-finite to min', () {
      expect(clampNetworkImageDecodePx(10, minPx: 64, maxPx: 2048), 64);
      expect(clampNetworkImageDecodePx(9000, minPx: 64, maxPx: 2048), 2048);
      expect(clampNetworkImageDecodePx(double.nan), 64);
      expect(clampNetworkImageDecodePx(double.infinity), 64);
    });

    test('rounds in-range values', () {
      expect(clampNetworkImageDecodePx(100.4), 100);
      expect(clampNetworkImageDecodePx(100.6), 101);
    });
  });

  group('resolveNetworkImageDecodeSize', () {
    test('explicit cache dimensions win over layout', () {
      final size = resolveNetworkImageDecodeSize(
        const NetworkImageDecodeInput(
          devicePixelRatio: 3,
          layoutWidth: 800,
          layoutHeight: 1200,
          explicitCacheWidth: 480,
          explicitCacheHeight: 720,
        ),
      );
      expect(size.cacheWidth, 480);
      expect(size.cacheHeight, 720);
      expect(size.hasDecodeTarget, isTrue);
    });

    test('explicit width only leaves height null', () {
      final size = resolveNetworkImageDecodeSize(
        const NetworkImageDecodeInput(
          devicePixelRatio: 2,
          widgetWidth: 400,
          explicitCacheWidth: 200,
        ),
      );
      expect(size.cacheWidth, 200);
      expect(size.cacheHeight, isNull);
    });

    test('landscape layout sets cacheWidth only', () {
      final size = resolveNetworkImageDecodeSize(
        const NetworkImageDecodeInput(
          devicePixelRatio: 2,
          layoutWidth: 400,
          layoutHeight: 200,
        ),
      );
      expect(size.cacheWidth, 800);
      expect(size.cacheHeight, isNull);
    });

    test('portrait layout sets cacheHeight only', () {
      final size = resolveNetworkImageDecodeSize(
        const NetworkImageDecodeInput(
          devicePixelRatio: 2,
          layoutWidth: 200,
          layoutHeight: 400,
        ),
      );
      expect(size.cacheWidth, isNull);
      expect(size.cacheHeight, 800);
    });

    test('widget size wins over layout size', () {
      final size = resolveNetworkImageDecodeSize(
        const NetworkImageDecodeInput(
          devicePixelRatio: 1,
          layoutWidth: 1000,
          layoutHeight: 1000,
          widgetWidth: 100,
          widgetHeight: 50,
        ),
      );
      expect(size.cacheWidth, 100);
      expect(size.cacheHeight, isNull);
    });

    test('width-only and height-only layout', () {
      final byW = resolveNetworkImageDecodeSize(
        const NetworkImageDecodeInput(
          devicePixelRatio: 2,
          layoutWidth: 120,
        ),
      );
      expect(byW.cacheWidth, 240);
      expect(byW.cacheHeight, isNull);

      final byH = resolveNetworkImageDecodeSize(
        const NetworkImageDecodeInput(
          devicePixelRatio: 2,
          layoutHeight: 80,
        ),
      );
      expect(byH.cacheWidth, isNull);
      expect(byH.cacheHeight, 160);
    });

    test('unbounded layout falls back to max decode px', () {
      final size = resolveNetworkImageDecodeSize(
        const NetworkImageDecodeInput(
          devicePixelRatio: 2,
          layoutWidth: double.infinity,
          layoutHeight: double.infinity,
        ),
        maxDecodePx: 1920,
      );
      expect(size.cacheWidth, 1920);
      expect(size.cacheHeight, isNull);
    });

    test('zero widget size is ignored; non-positive dpr treated as 1', () {
      final size = resolveNetworkImageDecodeSize(
        const NetworkImageDecodeInput(
          devicePixelRatio: 0,
          widgetWidth: 0,
          widgetHeight: double.nan,
          layoutWidth: 90,
          layoutHeight: 90,
        ),
      );
      expect(size.cacheWidth, 90);
    });

    test('NaN and infinite device pixel ratio treated as 1', () {
      final nanDpr = resolveNetworkImageDecodeSize(
        const NetworkImageDecodeInput(
          devicePixelRatio: double.nan,
          widgetWidth: 80,
          widgetHeight: 40,
        ),
      );
      expect(nanDpr.cacheWidth, 80);

      final infDpr = resolveNetworkImageDecodeSize(
        const NetworkImageDecodeInput(
          devicePixelRatio: double.infinity,
          widgetWidth: 80,
          widgetHeight: 40,
        ),
      );
      expect(infDpr.cacheWidth, 80);
    });

    test('tiny and huge logical sizes clamp', () {
      final tiny = resolveNetworkImageDecodeSize(
        const NetworkImageDecodeInput(
          devicePixelRatio: 1,
          widgetWidth: 10,
        ),
        minDecodePx: 64,
        maxDecodePx: 2048,
      );
      expect(tiny.cacheWidth, 64);

      final huge = resolveNetworkImageDecodeSize(
        const NetworkImageDecodeInput(
          devicePixelRatio: 3,
          widgetWidth: 4000,
        ),
        minDecodePx: 64,
        maxDecodePx: 2048,
      );
      expect(huge.cacheWidth, 2048);
    });

    test('app helper uses AppConstants decode floor', () {
      final size = resolveAppNetworkImageDecodeSize(
        const NetworkImageDecodeInput(
          devicePixelRatio: 1,
          widgetWidth: 10,
        ),
      );
      expect(size.cacheWidth, AppConstants.kNetworkImageMinDecodePx);
    });

    test('downsample false keeps full resolution unless explicit cache is set',
        () {
      final full = resolveAppNetworkImageDecodeSize(
        const NetworkImageDecodeInput(
          devicePixelRatio: 2,
          layoutWidth: 400,
          layoutHeight: 800,
        ),
        downsample: false,
      );
      expect(full.cacheWidth, isNull);
      expect(full.cacheHeight, isNull);
      expect(full.hasDecodeTarget, isFalse);

      final explicit = resolveAppNetworkImageDecodeSize(
        const NetworkImageDecodeInput(
          devicePixelRatio: 2,
          layoutWidth: 400,
          layoutHeight: 800,
          explicitCacheWidth: 480,
        ),
        downsample: false,
      );
      expect(explicit.cacheWidth, 480);
      expect(explicit.cacheHeight, isNull);
    });
  });

  group('resizeImageProviderIfNeeded', () {
    test('wraps when a decode target is set', () {
      const base = NetworkImage('https://example.com/a.jpg');
      final wrapped = resizeImageProviderIfNeeded(
        base,
        const NetworkImageDecodeSize(cacheWidth: 320),
      );
      expect(wrapped, isA<ResizeImage>());
    });

    test('returns the same provider when no decode target', () {
      const base = NetworkImage('https://example.com/a.jpg');
      final same = resizeImageProviderIfNeeded(
        base,
        const NetworkImageDecodeSize(),
      );
      expect(identical(same, base), isTrue);
      expect(const NetworkImageDecodeSize().hasDecodeTarget, isFalse);
    });
  });
}
