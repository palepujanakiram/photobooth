import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/photo_generate/photo_generate_viewmodel.dart';
import 'package:photobooth/screens/theme_selection/theme_model.dart';
import 'package:photobooth/utils/constants.dart';
import 'package:photobooth/utils/print_orientation.dart';
import 'package:photobooth/utils/print_size_helpers.dart';

void main() {
  group('resolveNetworkPrintSizeForImage', () {
    test('prefers image printSize', () {
      expect(
        resolveNetworkPrintSizeForImage(
          imagePrintSize: AppConstants.kPrintSizeStripDual2x6,
          orientation: PrintOrientation.portrait,
          sessionOverride: AppConstants.kPrintSizePortrait4x6,
        ),
        AppConstants.kPrintSizeStripDual2x6,
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
    test('backfills missing AI printSize to portrait 4x6', () {
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
      ]);
      expect(out[0].printSize, AppConstants.kPrintSizeStripDual2x6);
      expect(out[1].printSize, AppConstants.kPrintSizePortrait4x6);
    });
  });

  group('resolveStaffNetworkPrintSize', () {
    test('matches strip composite ignoring query params', () {
      expect(
        resolveStaffNetworkPrintSize(
          imageUrl: 'https://cdn/strip.jpg?sessionId=abc',
          stripCompositeUrl: 'https://cdn/strip.jpg',
        ),
        AppConstants.kPrintSizeStripDual2x6,
      );
    });

    test('matches strip composite ignoring trailing slash', () {
      expect(
        resolveStaffNetworkPrintSize(
          imageUrl: 'https://cdn/strip.jpg/',
          stripCompositeUrl: 'https://cdn/strip.jpg',
        ),
        AppConstants.kPrintSizeStripDual2x6,
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
  });

  test('isStripDualPrintSize', () {
    expect(isStripDualPrintSize(AppConstants.kPrintSizeStripDual2x6), isTrue);
    expect(isStripDualPrintSize(AppConstants.kPrintSizePortrait4x6), isFalse);
    expect(isStripDualPrintSize(null), isFalse);
  });
}
