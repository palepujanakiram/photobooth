import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/photo_capture/photo_model.dart';
import 'package:photobooth/screens/photo_generate/generation_wait_helpers.dart';
import 'package:photobooth/screens/photo_generate/photo_generate_viewmodel.dart';
import 'package:photobooth/screens/theme_selection/theme_model.dart';
import 'package:photobooth/utils/app_strings.dart';

void main() {
  const theme = ThemeModel(
    id: 't1',
    categoryId: 'c1',
    name: 'Vintage Noir',
    description: 'd',
    promptText: 'p',
    sampleImageUrl: 'https://example.com/sample.jpg',
  );

  final photo = PhotoModel(
    id: 'p1',
    imageFile: XFile('/tmp/photo_test.jpg'),
    capturedAt: DateTime.utc(2026, 1, 2),
  );

  group('generationWaitRotatingCopy', () {
    test('rotates every 8 seconds', () {
      expect(generationWaitRotatingCopy(0), kGenerationWaitRotatingCopy.first);
      expect(generationWaitRotatingCopy(8), kGenerationWaitRotatingCopy[1]);
      expect(
        generationWaitRotatingCopy(8 * kGenerationWaitRotatingCopy.length),
        kGenerationWaitRotatingCopy.first,
      );
    });
  });

  group('generationWaitCommentaryEnabled', () {
    test('enabled on kiosk by default', () {
      expect(
        generationWaitCommentaryEnabled(isWeb: false, showGenerationCommentary: false),
        isTrue,
      );
    });

    test('web follows settings flag', () {
      expect(
        generationWaitCommentaryEnabled(isWeb: true, showGenerationCommentary: true),
        isTrue,
      );
      expect(
        generationWaitCommentaryEnabled(isWeb: true, showGenerationCommentary: false),
        isFalse,
      );
    });
  });

  group('generationWaitEffectiveProgress', () {
    test('uses pseudo progress until server previews land', () {
      expect(
        generationWaitEffectiveProgress(
          pipelineProgress: 0,
          elapsedSeconds: 22,
          hasServerPreviews: false,
        ),
        closeTo(0.137, 0.01),
      );
    });

    test('defers to real pipeline progress when available', () {
      expect(
        generationWaitEffectiveProgress(
          pipelineProgress: 0.42,
          elapsedSeconds: 5,
          hasServerPreviews: true,
        ),
        0.42,
      );
    });
  });

  group('generationWaitPseudoStoryboardIndex', () {
    test('advances with elapsed time', () {
      expect(generationWaitPseudoStoryboardIndex(0), 0);
      expect(generationWaitPseudoStoryboardIndex(10), 1);
      expect(generationWaitPseudoStoryboardIndex(20), 2);
      expect(generationWaitPseudoStoryboardIndex(40), 3);
    });
  });

  group('previewUrlFromGenerationRunSteps', () {
    test('finds canonical stage preview url', () {
      const steps = [
        GenerationRunStepPreview(
          stage: 'preprocess',
          status: 'complete',
          previewUrl: 'https://example.com/pre.jpg',
        ),
      ];
      expect(
        previewUrlFromGenerationRunSteps(steps, 'preprocessing'),
        'https://example.com/pre.jpg',
      );
    });
  });

  group('polishingStartedFromGenerationRunSteps', () {
    test('true when polish stage is active', () {
      const steps = [
        GenerationRunStepPreview(
          stage: 'scene_lighting',
          status: 'active',
        ),
      ];
      expect(polishingStartedFromGenerationRunSteps(steps), isTrue);
    });
  });

  group('resolveGenerationWaitPresentation', () {
    test('uses rotating copy before server previews', () {
      final vm = PhotoGenerateViewModel();
      vm.initialize(photo, theme);
      final presentation = resolveGenerationWaitPresentation(
        vm,
        commentaryEnabled: true,
      );
      expect(presentation.storyboardIndex, 0);
      expect(presentation.headline, AppStrings.generationWaitHeadlineStarting);
      expect(
        presentation.description,
        generationWaitRotatingCopy(vm.elapsedSeconds),
      );
      expect(presentation.stageChanged, isFalse);
    });
  });
}
