import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/dnp/dnp_print_image_prepare.dart';
import 'package:photobooth/utils/constants.dart';

void main() {
  group('resolveStaffDnpPrintSize', () {
    test('keeps strip dual size regardless of portrait dimensions', () {
      expect(
        resolveStaffDnpPrintSize(
          imageUrl: 'https://cdn/strip.jpg',
          stripCompositeUrl: 'https://cdn/strip.jpg',
          orientedDimensions: (width: 900, height: 1800),
        ),
        AppConstants.kPrintSizeStripDual2x6,
      );
    });

    test('uses portrait 4x6 for upright AI aspect when session token is ambiguous', () {
      expect(
        resolveStaffDnpPrintSize(
          imageUrl: 'https://cdn/ai.jpg',
          sessionPrintSize: AppConstants.kPrintSizeLandscape6x4,
          orientedDimensions: (width: 1200, height: 1800),
        ),
        AppConstants.kPrintSizePortrait4x6,
      );
    });

    test('uses landscape 6x4 for wide aspect', () {
      expect(
        resolveStaffDnpPrintSize(
          imageUrl: 'https://cdn/wide.jpg',
          orientedDimensions: (width: 1800, height: 1200),
        ),
        AppConstants.kPrintSizeLandscape6x4,
      );
    });

    test('falls back to session token when dimensions unknown', () {
      expect(
        resolveStaffDnpPrintSize(
          imageUrl: 'https://cdn/ai.jpg',
          sessionPrintSize: AppConstants.kPrintSizePortrait4x6,
        ),
        AppConstants.kPrintSizePortrait4x6,
      );
    });
  });

  group('orientedDimensionsFromBytes', () {
    test('returns null for invalid bytes', () {
      expect(orientedDimensionsFromBytes(Uint8List.fromList([0, 1, 2])), isNull);
    });
  });
}
