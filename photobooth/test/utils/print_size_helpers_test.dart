import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/photo_generate/photo_generate_viewmodel.dart';
import 'package:photobooth/screens/theme_selection/theme_model.dart';
import 'package:photobooth/utils/constants.dart';
import 'package:photobooth/utils/print_orientation.dart';
import 'package:photobooth/utils/print_size_helpers.dart';

void main() {
  group('printSelectionThumbAspectRatio', () {
    test('matches Classic sheet deliverables', () {
      expect(
        printSelectionThumbAspectRatio(AppConstants.kPrintSizePortrait4x6),
        closeTo(4 / 6, 0.001),
      );
      expect(
        printSelectionThumbAspectRatio(AppConstants.kPrintSizeLandscape6x4),
        closeTo(6 / 4, 0.001),
      );
      expect(
        printSelectionThumbAspectRatio(AppConstants.kPrintSizeStripDual2x6),
        closeTo(4 / 6, 0.001),
      );
      expect(printSelectionThumbAspectRatio(null), closeTo(4 / 6, 0.001));
    });
  });

  group('fitPrintSelectionTile', () {
    test('fits a portrait 4x6 inside the viewport', () {
      final size = fitPrintSelectionTile(
        maxWidth: 1400,
        maxHeight: 700,
        printAspectWidthOverHeight: 4 / 6,
      );
      expect(size.height, lessThanOrEqualTo(700));
      expect(size.width, lessThanOrEqualTo(1400));
      expect(size.width, closeTo((size.height - 42) * (4 / 6), 0.5));
    });

    test('fits a landscape 6x4 when width is the constraint', () {
      final size = fitPrintSelectionTile(
        maxWidth: 400,
        maxHeight: 800,
        printAspectWidthOverHeight: 6 / 4,
        captionBand: 40,
      );
      expect(size.width, 400);
      expect(size.height, closeTo(400 / (6 / 4) + 40, 0.5));
    });

    test('returns zero for empty constraints', () {
      expect(
        fitPrintSelectionTile(
          maxWidth: 0,
          maxHeight: 100,
          printAspectWidthOverHeight: 4 / 6,
        ),
        Size.zero,
      );
      expect(
        fitPrintSelectionTile(
          maxWidth: 100,
          maxHeight: double.nan,
          printAspectWidthOverHeight: 4 / 6,
        ),
        Size.zero,
      );
    });

    test('clamps tile height when the caption band exceeds max height', () {
      final size = fitPrintSelectionTile(
        maxWidth: 300,
        maxHeight: 20,
        printAspectWidthOverHeight: 4 / 6,
        captionBand: 40,
      );
      expect(size.height, 20);
      expect(size.width, greaterThan(0));
    });

    test('falls back when aspect or caption band is invalid', () {
      final size = fitPrintSelectionTile(
        maxWidth: 300,
        maxHeight: 200,
        printAspectWidthOverHeight: 0,
        captionBand: -4,
      );
      expect(size.width, greaterThan(0));
      expect(size.height, lessThanOrEqualTo(200));
    });
  });

  group('resolveNetworkPrintSizeForImage', () {
    test('prefers fixed strip printSize over orientation', () {
      expect(
        resolveNetworkPrintSizeForImage(
          imagePrintSize: AppConstants.kPrintSizeStripDual2x6,
          orientation: PrintOrientation.landscape,
          sessionOverride: AppConstants.kPrintSizePortrait4x6,
        ),
        AppConstants.kPrintSizeStripDual2x6,
      );
    });

    test('uses customer landscape over default AI s4x6 on image', () {
      expect(
        resolveNetworkPrintSizeForImage(
          imagePrintSize: AppConstants.kPrintSizePortrait4x6,
          orientation: PrintOrientation.landscape,
        ),
        AppConstants.kPrintSizeLandscape6x4,
      );
    });

    test('uses customer portrait over default AI s4x6 on image', () {
      expect(
        resolveNetworkPrintSizeForImage(
          imagePrintSize: AppConstants.kPrintSizePortrait4x6,
          orientation: PrintOrientation.portrait,
        ),
        AppConstants.kPrintSizePortrait4x6,
      );
    });

    test('does not apply strip session override to unsized AI images', () {
      expect(
        resolveNetworkPrintSizeForImage(
          imagePrintSize: null,
          orientation: PrintOrientation.portrait,
          sessionOverride: AppConstants.kPrintSizeStripDual2x6,
        ),
        AppConstants.kPrintSizePortrait4x6,
      );
    });

    test('Classic 1-shot never uses dual-strip cutter', () {
      expect(
        resolveNetworkPrintSizeForImage(
          imagePrintSize: AppConstants.kPrintSizeStripDual2x6,
          orientation: PrintOrientation.portrait,
          sessionOverride: AppConstants.kPrintSizeStripDual2x6,
          classicComposeShotCount: 1,
        ),
        AppConstants.kPrintSizePortrait4x6,
      );
      expect(
        resolveNetworkPrintSizeForImage(
          imagePrintSize: AppConstants.kPrintSizeLandscape6x4,
          orientation: PrintOrientation.portrait,
          classicComposeShotCount: 1,
        ),
        AppConstants.kPrintSizeLandscape6x4,
      );
    });

    test('Classic 3-shot strip keeps the 2-inch cutter', () {
      expect(
        resolveNetworkPrintSizeForImage(
          imagePrintSize: AppConstants.kPrintSizeStripDual2x6,
          orientation: PrintOrientation.portrait,
          classicComposeShotCount: 3,
        ),
        AppConstants.kPrintSizeStripDual2x6,
      );
    });

    test('AI in a 3-shot session is never dual-strip cutter', () {
      expect(
        resolveNetworkPrintSizeForImage(
          imagePrintSize: AppConstants.kPrintSizePortrait4x6,
          orientation: PrintOrientation.portrait,
          sessionOverride: AppConstants.kPrintSizeStripDual2x6,
          classicComposeShotCount: 3,
        ),
        AppConstants.kPrintSizePortrait4x6,
      );
      expect(
        resolveNetworkPrintSizeForImage(
          imagePrintSize: AppConstants.kPrintSizePortrait4x6,
          orientation: PrintOrientation.landscape,
          sessionOverride: AppConstants.kPrintSizeStripDual2x6,
          classicComposeShotCount: 3,
        ),
        AppConstants.kPrintSizeLandscape6x4,
      );
    });

    test('uses non-strip session override when image has no size', () {
      expect(
        resolveNetworkPrintSizeForImage(
          imagePrintSize: '  ',
          orientation: PrintOrientation.portrait,
          sessionOverride: AppConstants.kPrintSizeLandscape6x4,
        ),
        AppConstants.kPrintSizeLandscape6x4,
      );
    });

    test('falls back to orientation printSize', () {
      expect(
        resolveNetworkPrintSizeForImage(
          imagePrintSize: null,
          orientation: PrintOrientation.landscape,
          sessionOverride: null,
        ),
        AppConstants.kPrintSizeLandscape6x4,
      );
    });
  });

  group('ensureGeneratedImagePrintSizes', () {
    test('backfills missing AI printSize from orientation', () {
      final theme = ThemeModel(
        id: 't1',
        categoryId: 'c',
        name: 'Theme',
        description: '',
        promptText: '',
      );
      final out = ensureGeneratedImagePrintSizes([
        GeneratedImage(
          id: 'strip',
          imageUrl: 'https://cdn/strip.jpg',
          theme: theme,
          printSize: AppConstants.kPrintSizeStripDual2x6,
        ),
        GeneratedImage(
          id: 'ai',
          imageUrl: 'https://cdn/ai.jpg',
          theme: theme,
        ),
      ], orientation: PrintOrientation.landscape);
      expect(out[0].printSize, AppConstants.kPrintSizeStripDual2x6);
      expect(out[1].printSize, AppConstants.kPrintSizeLandscape6x4);
    });

    test('overrides default AI s4x6 when customer chose landscape', () {
      final theme = ThemeModel(
        id: 't1',
        categoryId: 'c',
        name: 'Theme',
        description: '',
        promptText: '',
      );
      final out = ensureGeneratedImagePrintSizes([
        GeneratedImage(
          id: 'ai',
          imageUrl: 'https://cdn/ai.jpg',
          theme: theme,
          printSize: AppConstants.kPrintSizePortrait4x6,
        ),
      ], orientation: PrintOrientation.landscape);
      expect(out.single.printSize, AppConstants.kPrintSizeLandscape6x4);
    });
  });

  group('resolveClassicComposePrintSize', () {
    test('one-shot Classic defaults to landscape 6x4', () {
      expect(
        resolveClassicComposePrintSize(
          imageCount: 1,
          apiPrintSize: AppConstants.kPrintSizeStripDual2x6,
        ),
        AppConstants.kPrintSizeLandscape6x4,
      );
      expect(
        resolveClassicComposePrintSize(imageCount: 1),
        AppConstants.kPrintSizeLandscape6x4,
      );
    });

    test('one-shot Classic portrait uses 4x6', () {
      expect(
        resolveClassicComposePrintSize(
          imageCount: 1,
          orientation: PrintOrientation.portrait,
        ),
        AppConstants.kPrintSizePortrait4x6,
      );
    });

    test('three-shot Classic is always dual 6x2', () {
      expect(
        resolveClassicComposePrintSize(
          imageCount: 3,
          apiPrintSize: AppConstants.kPrintSizeStripDual2x6,
        ),
        AppConstants.kPrintSizeStripDual2x6,
      );
      expect(
        resolveClassicComposePrintSize(
          imageCount: 3,
          orientation: PrintOrientation.landscape,
        ),
        AppConstants.kPrintSizeStripDual2x6,
      );
    });

    test('four-shot Classic defaults to dual strip when API omits size', () {
      expect(
        resolveClassicComposePrintSize(imageCount: 4),
        AppConstants.kPrintSizeStripDual2x6,
      );
    });

    test('four-shot Classic stays dual 6x2 even in landscape', () {
      expect(
        resolveClassicComposePrintSize(
          imageCount: 4,
          orientation: PrintOrientation.landscape,
          apiPrintSize: AppConstants.kPrintSizeLandscape6x4,
        ),
        AppConstants.kPrintSizeStripDual2x6,
      );
    });
  });

  group('resolveFlashbackCartPrintSize', () {
    test('Classic 1-shot defaults to uncut orientation size', () {
      expect(
        resolveFlashbackCartPrintSize(
          imagePrintSize: null,
          fallbackPrintSize: AppConstants.kPrintSizeStripDual2x6,
          classicComposeShotCount: 1,
          orientation: PrintOrientation.portrait,
        ),
        AppConstants.kPrintSizePortrait4x6,
      );
    });

    test('3-shot keeps dual strip when printSize omitted', () {
      expect(
        resolveFlashbackCartPrintSize(
          imagePrintSize: null,
          classicComposeShotCount: 3,
        ),
        AppConstants.kPrintSizeStripDual2x6,
      );
    });
  });

  group('resolveClassicCheckoutSessionPrintSize', () {
    ThemeModel _theme() => ThemeModel(
          id: 't1',
          categoryId: 'c',
          name: 'Theme',
          description: '',
          promptText: '',
        );

    test('Classic 1-shot checkout hint is never dual-strip', () {
      expect(
        resolveClassicCheckoutSessionPrintSize(
          selected: [
            GeneratedImage(
              id: 'g',
              imageUrl: 'https://cdn/one.jpg',
              theme: _theme(),
              printSize: AppConstants.kPrintSizeStripDual2x6,
            ),
          ],
          stripPrintSize: AppConstants.kPrintSizeStripDual2x6,
          classicComposeShotCount: 1,
          orientation: PrintOrientation.portrait,
        ),
        AppConstants.kPrintSizePortrait4x6,
      );
    });

    test('empty selected returns null', () {
      expect(
        resolveClassicCheckoutSessionPrintSize(
          selected: [],
          orientation: PrintOrientation.portrait,
        ),
        isNull,
      );
    });

    test('unanimous print size across images is returned', () {
      final t = _theme();
      expect(
        resolveClassicCheckoutSessionPrintSize(
          selected: [
            GeneratedImage(
                id: 'a',
                imageUrl: 'u',
                theme: t,
                printSize: AppConstants.kPrintSizeStripDual2x6),
            GeneratedImage(
                id: 'b',
                imageUrl: 'u',
                theme: t,
                printSize: AppConstants.kPrintSizeStripDual2x6),
          ],
          orientation: PrintOrientation.portrait,
        ),
        AppConstants.kPrintSizeStripDual2x6,
      );
    });

    test('landscape6x4 wins when present without dual-strip', () {
      final t = _theme();
      expect(
        resolveClassicCheckoutSessionPrintSize(
          selected: [
            GeneratedImage(
                id: 'a',
                imageUrl: 'u',
                theme: t,
                printSize: AppConstants.kPrintSizeLandscape6x4),
            GeneratedImage(
                id: 'b',
                imageUrl: 'u',
                theme: t,
                printSize: AppConstants.kPrintSizePortrait4x6),
          ],
          orientation: PrintOrientation.portrait,
        ),
        AppConstants.kPrintSizeLandscape6x4,
      );
    });

    test('stripPrintSize hint returned when sizes are mixed', () {
      final t = _theme();
      expect(
        resolveClassicCheckoutSessionPrintSize(
          selected: [
            GeneratedImage(
                id: 'a', imageUrl: 'u', theme: t, printSize: 'size_a'),
            GeneratedImage(
                id: 'b', imageUrl: 'u', theme: t, printSize: 'size_b'),
          ],
          stripPrintSize: AppConstants.kPrintSizeStripDual2x6,
          orientation: PrintOrientation.portrait,
        ),
        AppConstants.kPrintSizeStripDual2x6,
      );
    });

    test('returns null when mixed sizes and no hint', () {
      final t = _theme();
      expect(
        resolveClassicCheckoutSessionPrintSize(
          selected: [
            GeneratedImage(
                id: 'a', imageUrl: 'u', theme: t, printSize: 'size_a'),
            GeneratedImage(
                id: 'b', imageUrl: 'u', theme: t, printSize: 'size_b'),
          ],
          orientation: PrintOrientation.portrait,
        ),
        isNull,
      );
    });
  });

  group('resolveStaffNetworkPrintSize', () {
    test('session dual token without strip URL does not cut AI', () {
      expect(
        resolveStaffNetworkPrintSize(
          imageUrl: 'https://cdn/ai.jpg',
          sessionPrintSize: AppConstants.kPrintSizeStripDual2x6,
        ),
        AppConstants.kPrintSizePortrait4x6,
      );
    });

    test('3-shot session dual token keeps cutter on the strip JPEG', () {
      expect(
        resolveStaffNetworkPrintSize(
          imageUrl: 'https://cdn/strip.jpg',
          sessionPrintSize: AppConstants.kPrintSizeStripDual2x6,
          classicComposeShotCount: 3,
        ),
        AppConstants.kPrintSizeStripDual2x6,
      );
    });

    test('matches strip composite ignoring query params', () {
      expect(
        resolveStaffNetworkPrintSize(
          imageUrl: 'https://cdn/strip.jpg?sessionId=abc',
          stripCompositeUrl: 'https://cdn/strip.jpg',
        ),
        AppConstants.kPrintSizeStripDual2x6,
      );
    });

    test('prefers explicit session printSize over strip URL match', () {
      expect(
        resolveStaffNetworkPrintSize(
          imageUrl: 'https://cdn/single.jpg',
          stripCompositeUrl: 'https://cdn/single.jpg',
          sessionPrintSize: AppConstants.kPrintSizeLandscape6x4,
        ),
        AppConstants.kPrintSizeLandscape6x4,
      );
    });

    test('single-shot Classic uses s6x4 when URL equals strip composite', () {
      expect(
        resolveStaffNetworkPrintSize(
          imageUrl: 'https://cdn/single.jpg',
          stripCompositeUrl: 'https://cdn/single.jpg',
          classicComposeShotCount: 1,
        ),
        AppConstants.kPrintSizePortrait4x6,
      );
    });

    test('single-shot Classic ignores catalog dual-strip session token', () {
      expect(
        resolveStaffNetworkPrintSize(
          imageUrl: 'https://cdn/single.jpg',
          stripCompositeUrl: 'https://cdn/single.jpg',
          sessionPrintSize: AppConstants.kPrintSizeStripDual2x6,
          classicComposeShotCount: 1,
        ),
        AppConstants.kPrintSizePortrait4x6,
      );
    });

    test('three-shot Classic strip keeps dual-strip cutter', () {
      expect(
        resolveStaffNetworkPrintSize(
          imageUrl: 'https://cdn/strip.jpg',
          stripCompositeUrl: 'https://cdn/strip.jpg',
          sessionPrintSize: AppConstants.kPrintSizeStripDual2x6,
          classicComposeShotCount: 3,
        ),
        AppConstants.kPrintSizeStripDual2x6,
      );
    });

    test('matches strip composite ignoring a trailing slash', () {
      expect(
        resolveStaffNetworkPrintSize(
          imageUrl: 'https://cdn/strip.jpg/',
          stripCompositeUrl: 'https://cdn/strip.jpg',
        ),
        AppConstants.kPrintSizeStripDual2x6,
      );
    });

    test('AI page in a 3-shot session is never dual-strip cutter', () {
      expect(
        resolveStaffNetworkPrintSize(
          imageUrl: 'https://cdn/ai.jpg',
          stripCompositeUrl: 'https://cdn/strip.jpg',
          sessionPrintSize: AppConstants.kPrintSizeStripDual2x6,
          classicComposeShotCount: 3,
        ),
        AppConstants.kPrintSizePortrait4x6,
      );
      expect(
        resolveStaffNetworkPrintSize(
          imageUrl: 'https://cdn/ai.jpg',
          stripCompositeUrl: 'https://cdn/strip.jpg',
          sessionPrintSize: AppConstants.kPrintSizeLandscape6x4,
          classicComposeShotCount: 3,
        ),
        AppConstants.kPrintSizeLandscape6x4,
      );
    });

    test('AI URLs use portrait 4x6', () {
      expect(
        resolveStaffNetworkPrintSize(
          imageUrl: 'https://cdn/ai.jpg',
          stripCompositeUrl: 'https://cdn/strip.jpg',
        ),
        AppConstants.kPrintSizePortrait4x6,
      );
    });

    test('defaults to 4x6 when strip URL unknown', () {
      expect(
        resolveStaffNetworkPrintSize(
          imageUrl: 'https://cdn/strip.jpg',
          stripCompositeUrl: null,
        ),
        AppConstants.kPrintSizePortrait4x6,
      );
    });

    test('matches Classic single 6x4 print URL', () {
      expect(
        resolveStaffNetworkPrintSize(
          imageUrl: 'https://cdn/single6x4.jpg',
          stripCompositeUrl: 'https://cdn/strip.jpg',
          single6x4Url: 'https://cdn/single6x4.jpg',
        ),
        AppConstants.kPrintSizeLandscape6x4,
      );
    });
  });

  test('classicComposeUsesDualStripCutter is 3-shot and 4-shot only', () {
    expect(classicComposeUsesDualStripCutter(1), isFalse);
    expect(classicComposeUsesDualStripCutter(3), isTrue);
    expect(classicComposeUsesDualStripCutter(4), isTrue);
    expect(classicComposeUsesDualStripCutter(null), isFalse);
  });

  test('isStripDualPrintSize', () {
    expect(isStripDualPrintSize(AppConstants.kPrintSizeStripDual2x6), isTrue);
    expect(isStripDualPrintSize(AppConstants.kPrintSizePortrait4x6), isFalse);
    expect(isStripDualPrintSize(null), isFalse);
  });

  test('isOrientationSelectablePrintSize', () {
    expect(isOrientationSelectablePrintSize(null), isTrue);
    expect(
      isOrientationSelectablePrintSize(AppConstants.kPrintSizePortrait4x6),
      isTrue,
    );
    expect(
      isOrientationSelectablePrintSize(AppConstants.kPrintSizeLandscape6x4),
      isTrue,
    );
    expect(
      isOrientationSelectablePrintSize(AppConstants.kPrintSizeStripDual2x6),
      isFalse,
    );
  });
}
