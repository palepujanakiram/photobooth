import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/photo_generate/photo_generate_viewmodel.dart';
import 'package:photobooth/services/print_selection_coordinator.dart';
import 'package:photobooth/utils/ai_attempts_budget.dart';
import 'package:photobooth/utils/constants.dart';

import '../fixtures/theme_fixtures.dart';

void main() {
  tearDown(() {
    PrintSelectionCoordinator.instance.clear();
  });

  group('effectiveAiAttemptsUsed', () {
    test('ignores Classic strip-only attemptsUsed burn', () {
      expect(
        effectiveAiAttemptsUsed(
          attemptsUsed: 1,
          generatedImages: ['https://cdn/strip.jpg'],
          stripCompositeUrl: 'https://cdn/strip.jpg',
        ),
        0,
      );
    });

    test('counts real AI generations after strip', () {
      expect(
        effectiveAiAttemptsUsed(
          attemptsUsed: 2,
          generatedImages: [
            'https://cdn/strip.jpg',
            'https://cdn/ai.jpg',
          ],
          stripCompositeUrl: 'https://cdn/strip.jpg',
        ),
        1,
      );
    });

    test('pure AI sessions unchanged', () {
      expect(
        effectiveAiAttemptsUsed(
          attemptsUsed: 2,
          generatedImages: [
            'https://cdn/a.jpg',
            'https://cdn/b.jpg',
          ],
          stripCompositeUrl: null,
        ),
        2,
      );
    });
  });

  test('stripCompositeUrlFromPrintSelection reads hub strip', () {
    PrintSelectionCoordinator.instance.seed(
      seedImages: [
        GeneratedImage(
          id: 'strip',
          imageUrl: 'https://cdn/strip.jpg',
          theme: sampleTheme('strip'),
          isSelected: true,
          printSize: AppConstants.kPrintSizeStripDual2x6,
        ),
      ],
    );
    expect(
      stripCompositeUrlFromPrintSelection(),
      'https://cdn/strip.jpg',
    );
  });

  test('stripCompositeUrlFromPrintSelection matches custom stripPrintSize', () {
    PrintSelectionCoordinator.instance.seed(
      seedImages: [
        GeneratedImage(
          id: 'strip',
          imageUrl: 'https://cdn/custom-strip.jpg',
          theme: sampleTheme('strip'),
          isSelected: true,
          printSize: 'custom_size',
        ),
      ],
      stripPrintSize: 'custom_size',
    );
    expect(
      stripCompositeUrlFromPrintSelection(),
      'https://cdn/custom-strip.jpg',
    );
  });
}
