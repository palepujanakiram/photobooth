import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/photo_capture/photo_model.dart';
import 'package:photobooth/screens/photo_generate/generation_wait_helpers.dart';
import 'package:photobooth/screens/photo_generate/photo_generate_viewmodel.dart';
import 'package:photobooth/screens/theme_selection/theme_model.dart';
import 'package:photobooth/utils/app_strings.dart';
import 'package:photobooth/utils/constants.dart';
import 'package:photobooth/utils/print_orientation.dart';

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

  group('generationWaitShowAnticipationPhase', () {
    test('false when generation is not in progress', () {
      final vm = PhotoGenerateViewModel();
      vm.initialize(photo, theme);
      expect(generationWaitShowAnticipationPhase(vm), isFalse);
    });

    test('true while awaiting a fresh run id during regen', () {
      final vm = PhotoGenerateViewModel();
      vm.initialize(photo, theme);
      vm.prepareToAddStyle(theme);
      expect(vm.awaitingFreshRunId, isTrue);
      expect(generationWaitShowAnticipationPhase(vm), isTrue);
    });
  });

  group('computeTriesRemaining', () {
    test('clamps at zero and max', () {
      expect(
        computeTriesRemaining(maxAllowed: 3, attemptsUsed: 1),
        2,
      );
      expect(
        computeTriesRemaining(maxAllowed: 3, attemptsUsed: 5),
        0,
      );
    });
  });

  group('generationWaitDidYouKnowTip', () {
    test('rotates every 12 seconds', () {
      expect(
        generationWaitDidYouKnowTip(0),
        kGenerationWaitDidYouKnowTips.first,
      );
      expect(
        generationWaitDidYouKnowTip(12),
        kGenerationWaitDidYouKnowTips[1],
      );
    });
  });

  group('generationWaitStepperActiveIndex', () {
    test('starts at analyzing before previews', () {
      final vm = PhotoGenerateViewModel();
      vm.initialize(photo, theme);
      final presentation = resolveGenerationWaitPresentation(
        vm,
        commentaryEnabled: true,
      );
      expect(
        generationWaitStepperActiveIndex(vm, presentation),
        0,
      );
    });

    test('advances with pseudo storyboard during anticipation', () {
      final vm = PhotoGenerateViewModel();
      vm.initialize(photo, theme);
      const presentation = GenerationWaitPresentation(
        storyboardIndex: 2,
        stageTitle: '3 · REVEAL',
        headline: 'Rendering',
        description: 'Applying style',
        imageUrl: null,
        showPolishingOverlay: false,
        stageChanged: false,
      );
      expect(generationWaitStepperActiveIndex(vm, presentation), 2);
    });

    test('finalizing when polishing overlay is active', () {
      final vm = PhotoGenerateViewModel();
      vm.initialize(photo, theme);
      const presentation = GenerationWaitPresentation(
        storyboardIndex: 3,
        stageTitle: '4 · FINISH',
        headline: 'Finishing',
        description: 'Polish',
        imageUrl: 'https://example.com/ai.jpg',
        showPolishingOverlay: true,
        stageChanged: true,
      );
      expect(generationWaitStepperActiveIndex(vm, presentation), 2);
    });
  });

  group('generationWaitShouldShowLiveStatusCopy', () {
    test('hides generic vm progress headline', () {
      const presentation = GenerationWaitPresentation(
        storyboardIndex: 1,
        stageTitle: 'x',
        headline: 'Transforming your look...',
        description: 'Applying your style…',
        imageUrl: null,
        showPolishingOverlay: false,
        stageChanged: false,
      );
      expect(generationWaitShouldShowLiveStatusCopy(presentation), isFalse);
    });

    test('hides duplicate time expectation description', () {
      const presentation = GenerationWaitPresentation(
        storyboardIndex: 0,
        stageTitle: 'x',
        headline: 'Custom server message',
        description: AppStrings.generationWaitExpectation,
        imageUrl: null,
        showPolishingOverlay: false,
        stageChanged: false,
      );
      expect(generationWaitShouldShowLiveStatusCopy(presentation), isTrue);
    });
  });

  group('generationWaitHeroCellAspectRatio', () {
    test('portrait for solo and couples', () {
      expect(generationWaitUsesLandscapeCards(1), isFalse);
      expect(generationWaitUsesLandscapeCards(2), isFalse);
      expect(
        generationWaitHeroCellAspectRatio(2),
        AppConstants.kThemeSelectedCardAspectRatio,
      );
    });

    test('landscape for groups of three or more', () {
      expect(generationWaitUsesLandscapeCards(3), isTrue);
      expect(
        generationWaitHeroCellAspectRatio(3),
        AppConstants.kBeholdSingleResultDefaultAspectRatio,
      );
    });
  });

  group('generationWaitKioskCompareCellAspect', () {
    test('landscape when person count is a group', () {
      expect(
        generationWaitKioskCompareCellAspect(
          personCount: 4,
          printOrientation: PrintOrientation.portrait,
        ),
        AppConstants.kBeholdSingleResultDefaultAspectRatio,
      );
    });

    test('landscape when print orientation is landscape', () {
      expect(
        generationWaitKioskCompareCellAspect(
          personCount: 1,
          printOrientation: PrintOrientation.landscape,
        ),
        AppConstants.kBeholdSingleResultDefaultAspectRatio,
      );
    });

    test('uses decoded wide still before default portrait', () {
      expect(
        generationWaitKioskCompareCellAspect(
          personCount: 1,
          printOrientation: PrintOrientation.portrait,
          decodedImageAspect: 1.78,
        ),
        closeTo(1.78, 0.001),
      );
    });

    test('portrait for solo when still is tall', () {
      expect(
        generationWaitKioskCompareCellAspect(
          personCount: 1,
          printOrientation: PrintOrientation.portrait,
          decodedImageAspect: 0.75,
        ),
        AppConstants.kThemeSelectedCardAspectRatio,
      );
    });
  });

  group('computeThemeAnticipationHeroSize', () {
    test('fills tall portrait slot instead of a short landscape strip', () {
      final size = computeThemeAnticipationHeroSize(
        maxWidth: 720,
        maxHeight: 520,
      );
      expect(size.height, greaterThan(400));
      expect(size.width, lessThanOrEqualTo(720));
    });

    test('uses portrait cell aspect ratio by default', () {
      final size = computeThemeAnticipationHeroSize(
        maxWidth: 720,
        maxHeight: 520,
      );
      const gap = kGenerationWaitAnticipationCellGap;
      final cellW = (size.width - gap) / 2;
      final cellH = size.height - kGenerationWaitAnticipationLabelOverhead;
      expect(cellW / cellH, closeTo(3 / 4.5, 0.02));
    });

    test('uses landscape cell aspect for group sessions', () {
      final size = computeThemeAnticipationHeroSize(
        maxWidth: 720,
        maxHeight: 520,
        cellAspect: generationWaitHeroCellAspectRatio(3),
      );
      const gap = kGenerationWaitAnticipationCellGap;
      final cellW = (size.width - gap) / 2;
      final cellH = size.height - kGenerationWaitAnticipationLabelOverhead;
      expect(cellW / cellH, closeTo(3 / 2, 0.02));
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

  group('generationWaitShouldHoldUnbrandedAiReveal', () {
    test('holds until branded url exists when branding enabled', () {
      expect(
        generationWaitShouldHoldUnbrandedAiReveal(
          outputBrandingEnabled: true,
          brandedOutputUrl: null,
        ),
        isTrue,
      );
      expect(
        generationWaitShouldHoldUnbrandedAiReveal(
          outputBrandingEnabled: true,
          brandedOutputUrl: 'https://example.com/branded.jpg',
        ),
        isFalse,
      );
      expect(
        generationWaitShouldHoldUnbrandedAiReveal(
          outputBrandingEnabled: false,
          brandedOutputUrl: null,
        ),
        isFalse,
      );
    });
  });

  group('buildGenerationWaitPresentation', () {
    test('holds unbranded AI and keeps prior stage pixels', () {
      final presentation = buildGenerationWaitPresentation(
        const GenerationWaitPresentationInput(
          elapsedSeconds: 12,
          preprocessUrl: 'https://example.com/pre.jpg',
          bgUrl: 'https://example.com/bg.jpg',
          aiUrl: 'https://example.com/ai.jpg',
          brandedUrl: null,
          polishing: true,
          holdUnbrandedAi: true,
          progress: '',
          commentary: null,
        ),
      );
      expect(presentation.imageUrl, 'https://example.com/bg.jpg');
      expect(presentation.showPolishingOverlay, isTrue);
      expect(presentation.headline, AppStrings.generationWaitHeadlineFinishing);
      expect(
        presentation.description,
        AppStrings.generationWaitDescFinishing,
      );
      expect(presentation.storyboardIndex, 3);
    });

    test('reveals branded final when available', () {
      final presentation = buildGenerationWaitPresentation(
        const GenerationWaitPresentationInput(
          elapsedSeconds: 20,
          preprocessUrl: null,
          bgUrl: null,
          aiUrl: 'https://example.com/ai.jpg',
          brandedUrl: 'https://example.com/branded.jpg',
          polishing: true,
          holdUnbrandedAi: false,
          progress: '',
          commentary: null,
        ),
      );
      expect(presentation.imageUrl, 'https://example.com/branded.jpg');
      expect(presentation.showPolishingOverlay, isTrue);
    });

    test('still early-reveals AI when branding hold is off', () {
      final presentation = buildGenerationWaitPresentation(
        const GenerationWaitPresentationInput(
          elapsedSeconds: 10,
          preprocessUrl: null,
          bgUrl: null,
          aiUrl: 'https://example.com/ai.jpg',
          brandedUrl: null,
          polishing: false,
          holdUnbrandedAi: false,
          progress: '',
          commentary: null,
        ),
      );
      expect(presentation.imageUrl, 'https://example.com/ai.jpg');
      expect(presentation.storyboardIndex, 2);
      expect(presentation.showPolishingOverlay, isTrue);
    });
  });

  group('brandedGenerationOutputUrl', () {
    test('returns null when no generated or live slot urls exist', () {
      final vm = PhotoGenerateViewModel();
      vm.initialize(photo, theme);
      expect(brandedGenerationOutputUrl(vm), isNull);
    });
  });

  group('resolveGenerationEta', () {
    test('uses defaults when timing stats not loaded', () {
      final vm = PhotoGenerateViewModel();
      vm.initialize(photo, theme);
      final eta = resolveGenerationEta(vm);
      expect(eta.estimatedTotalSeconds, greaterThan(0));
      expect(eta.primaryLine, isNotEmpty);
    });
  });
}
