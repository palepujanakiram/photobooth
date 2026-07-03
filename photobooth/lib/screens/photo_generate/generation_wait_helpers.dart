import 'dart:math' as math;

import 'package:flutter/material.dart' show Alignment;

import 'photo_generate_viewmodel.dart';
import '../../utils/app_strings.dart';
import '../../utils/constants.dart';

/// Prefer the upper frame when cropping portrait captures in short cards.
const Alignment kGenerationWaitPortraitFaceAlignment = Alignment(0, -0.22);

/// Center crop for group captures in landscape anticipation cells.
const Alignment kGenerationWaitGroupCaptureAlignment = Alignment.center;

/// Groups (3+ people) use landscape cells so wide shots are not cropped at the sides.
bool generationWaitUsesLandscapeCards(int? personCount) {
  final count = personCount != null && personCount > 0 ? personCount : 1;
  return count > 2;
}

/// Width ÷ height for You | Style cells and cinematic hero during CREATE wait.
double generationWaitHeroCellAspectRatio(int? personCount) {
  return generationWaitUsesLandscapeCards(personCount)
      ? AppConstants.kBeholdSingleResultDefaultAspectRatio
      : AppConstants.kThemeSelectedCardAspectRatio;
}

Alignment generationWaitCaptureImageAlignment(int? personCount) {
  return generationWaitUsesLandscapeCards(personCount)
      ? kGenerationWaitGroupCaptureAlignment
      : kGenerationWaitPortraitFaceAlignment;
}

/// Vertical space for the You/Style labels above anticipation cells.
const double kGenerationWaitAnticipationLabelOverhead = 22;

/// Gap between the two anticipation cells.
const double kGenerationWaitAnticipationCellGap = 10;

/// Scripted status lines when the server has not sent an update yet.
const List<String> kGenerationWaitRotatingCopy = [
  'Removing the background…',
  'Applying your style…',
  'Balancing light and color…',
  'Almost there — great portraits take a moment',
  'Polishing the details…',
];

/// Rotating educational tips shown during the wait screen footer.
const List<String> kGenerationWaitDidYouKnowTips = [
  'Our AI analyzes your unique features to create a personalized portrait.',
  'Each style is trained on thousands of artistic references.',
  'Your original photo is never shared with third parties.',
  'The process combines computer vision and generative AI.',
];

/// Labels for the three-step generation wait stepper (index order).
const List<String> kGenerationWaitStepperLabels = [
  AppStrings.generationWaitStepAnalyzing,
  AppStrings.generationWaitStepTransforming,
  AppStrings.generationWaitStepFinalizing,
];

/// Presentation model for the generation wait hero + storyboard.
class GenerationWaitPresentation {
  const GenerationWaitPresentation({
    required this.storyboardIndex,
    required this.stageTitle,
    required this.headline,
    required this.description,
    required this.imageUrl,
    required this.showPolishingOverlay,
    required this.stageChanged,
  });

  final int storyboardIndex;
  final String stageTitle;
  final String headline;
  final String description;
  final String? imageUrl;
  final bool showPolishingOverlay;

  /// True when [storyboardIndex] advanced vs [previous].
  final bool stageChanged;
}

bool generationWaitHasPipelinePreviews(PhotoGenerateViewModel vm) {
  for (final s in vm.generationRunStepPreviews) {
    if ((s.previewUrl ?? '').trim().isNotEmpty) return true;
  }
  return false;
}

/// Early wait phase: collage + anticipation before server pipeline previews land.
bool generationWaitShowAnticipationPhase(PhotoGenerateViewModel vm) {
  if (!vm.isOperationInProgress) return false;
  if (vm.awaitingFreshRunId) return true;
  return !generationWaitHasPipelinePreviews(vm);
}

String generationWaitRotatingCopy(int elapsedSeconds) {
  if (elapsedSeconds <= 0) return kGenerationWaitRotatingCopy.first;
  final index = (elapsedSeconds ~/ 8) % kGenerationWaitRotatingCopy.length;
  return kGenerationWaitRotatingCopy[index];
}

String generationWaitDidYouKnowTip(int elapsedSeconds) {
  if (elapsedSeconds <= 0) return kGenerationWaitDidYouKnowTips.first;
  final index = (elapsedSeconds ~/ 12) % kGenerationWaitDidYouKnowTips.length;
  return kGenerationWaitDidYouKnowTips[index];
}

/// Active step for the 3-step wait UI: analyzing → transforming → finalizing.
int generationWaitStepperActiveIndex(
  PhotoGenerateViewModel vm,
  GenerationWaitPresentation presentation,
) {
  if (generationWaitPolishingStarted(vm) || presentation.showPolishingOverlay) {
    return 2;
  }
  if (previewUrlForStage(vm, 'ai_generation') != null) return 1;
  if (previewUrlForStage(vm, 'background_removal') != null) return 1;
  if (previewUrlForStage(vm, 'preprocessing') != null) return 0;
  if (generationWaitHasPipelinePreviews(vm)) return 1;
  if (presentation.storyboardIndex >= 2) return 2;
  if (presentation.storyboardIndex >= 1) return 1;
  return 0;
}

bool generationWaitCommentaryEnabled({
  required bool isWeb,
  required bool? showGenerationCommentary,
}) {
  if (!isWeb) return true;
  return showGenerationCommentary == true;
}

String? generationWaitCommentaryLine(
  PhotoGenerateViewModel vm, {
  required bool commentaryEnabled,
}) {
  if (!commentaryEnabled) return null;
  final commentary = vm.liveCommentary?.trim();
  if (commentary != null && commentary.isNotEmpty) return commentary;
  return vm.progressiveOneLiner;
}

/// Honest pseudo-progress until server pipeline previews arrive (caps ~28%).
double generationWaitEffectiveProgress({
  required double pipelineProgress,
  required int elapsedSeconds,
  required bool hasServerPreviews,
}) {
  if (pipelineProgress >= 0.08) return pipelineProgress.clamp(0.0, 1.0);
  if (hasServerPreviews) return pipelineProgress.clamp(0.0, 1.0);
  final pseudo = (elapsedSeconds / 45.0) * 0.28;
  return math.max(pipelineProgress, pseudo).clamp(0.0, 0.28);
}

/// Hide generic server/vm progress lines when act headline + chips already tell the story.
bool generationWaitShouldShowLiveStatusCopy(
  GenerationWaitPresentation presentation,
) {
  final headline = presentation.headline.trim();
  if (headline.isEmpty) return false;
  const hiddenHeadlines = {
    'Starting your transformation',
    'Transforming your look...',
    'Adding your new style...',
    'Your portrait is taking shape',
  };
  if (hiddenHeadlines.contains(headline)) return false;

  final description = presentation.description.trim();
  if (description.isEmpty) return true;

  if (description == AppStrings.generationWaitExpectation ||
      description == AppStrings.generationWaitTimeExpectation) {
    return !hiddenHeadlines.contains(headline);
  }
  return true;
}

int generationWaitPseudoStoryboardIndex(int elapsedSeconds) {
  if (elapsedSeconds < 6) return 0;
  if (elapsedSeconds < 18) return 1;
  if (elapsedSeconds < 32) return 2;
  return 3;
}

String? previewUrlFromGenerationRunSteps(
  List<GenerationRunStepPreview> steps,
  String stageKey,
) {
  final want = stageKey.trim().toLowerCase();
  for (final s in steps) {
    final key = canonicalPipelineStageKey(s.stage);
    if (key == want && (s.previewUrl ?? '').trim().isNotEmpty) {
      return s.previewUrl!.trim();
    }
  }
  return null;
}

String? previewUrlForStage(PhotoGenerateViewModel vm, String stageKey) {
  return previewUrlFromGenerationRunSteps(
    vm.generationRunStepPreviews,
    stageKey,
  );
}

bool polishingStartedFromGenerationRunSteps(
  List<GenerationRunStepPreview> steps,
) {
  for (final s in steps) {
    final key = canonicalPipelineStageKey(s.stage);
    switch (key) {
      case 'scene_lighting':
      case 'face_relight':
      case 'frame_composite':
      case 'upscaling':
      case 'exif_stamp':
      case 'c2pa_sign':
      case 'storage':
        if (s.isActive || s.isFinished) return true;
        break;
    }
  }
  return false;
}

bool generationWaitPolishingStarted(PhotoGenerateViewModel vm) {
  return polishingStartedFromGenerationRunSteps(vm.generationRunStepPreviews);
}

GenerationWaitPresentation resolveGenerationWaitPresentation(
  PhotoGenerateViewModel vm, {
  GenerationWaitPresentation? previous,
  required bool commentaryEnabled,
}) {
  final preprocessUrl = previewUrlForStage(vm, 'preprocessing');
  final bgUrl = previewUrlForStage(vm, 'background_removal');
  final aiUrl = previewUrlForStage(vm, 'ai_generation');
  final polishing = generationWaitPolishingStarted(vm);

  var index = generationWaitPseudoStoryboardIndex(vm.elapsedSeconds);
  var stageTitle = '1 · CAPTURE';
  var headline = AppStrings.generationWaitHeadlineStarting;
  var description = AppStrings.generationWaitExpectation;
  String? imageUrl;
  var showPolishingOverlay = false;

  final progress = vm.progressMessage.trim();
  final commentary = generationWaitCommentaryLine(
    vm,
    commentaryEnabled: commentaryEnabled,
  );

  if (aiUrl != null && polishing) {
    index = 3;
    stageTitle = '4 · FINISH';
    headline = AppStrings.generationWaitLiveRevealHeadline;
    description = AppStrings.generationWaitLiveRevealDesc;
    imageUrl = aiUrl;
    showPolishingOverlay = true;
  } else if (aiUrl != null) {
    index = 2;
    stageTitle = '3 · REVEAL';
    headline = AppStrings.generationWaitLiveRevealHeadline;
    description = AppStrings.generationWaitLiveRevealDesc;
    imageUrl = aiUrl;
    showPolishingOverlay = true;
  } else if (bgUrl != null) {
    index = 1;
    stageTitle = '2 · ISOLATE';
    headline = AppStrings.generationWaitLiveRevealHeadline;
    description = AppStrings.generationWaitLiveRevealDesc;
    imageUrl = bgUrl;
  } else if (preprocessUrl != null) {
    index = 0;
    stageTitle = '1 · CAPTURE';
    headline = AppStrings.generationWaitLiveRevealHeadline;
    description = AppStrings.generationWaitLiveRevealDesc;
    imageUrl = preprocessUrl;
  }

  if (progress.isNotEmpty) {
    headline = progress;
  }
  if (commentary != null && commentary.isNotEmpty) {
    description = commentary;
  } else if (imageUrl == null && progress.isEmpty) {
    description = generationWaitRotatingCopy(vm.elapsedSeconds);
  }

  final stageChanged =
      previous != null && previous.storyboardIndex < index;

  return GenerationWaitPresentation(
    storyboardIndex: index,
    stageTitle: stageTitle,
    headline: headline,
    description: description,
    imageUrl: imageUrl,
    showPolishingOverlay: showPolishingOverlay,
    stageChanged: stageChanged,
  );
}

/// Fits [aspect] (width ÷ height) inside a box.
({double width, double height}) fitGenerationWaitAspectInBox({
  required double maxWidth,
  required double maxHeight,
  required double aspect,
}) {
  late double width;
  late double height;
  if (maxWidth / maxHeight > aspect) {
    height = maxHeight;
    width = height * aspect;
  } else {
    width = maxWidth;
    height = width / aspect;
  }
  return (width: width, height: height);
}

/// Sizes the You | Style anticipation row (portrait solo/couple, landscape groups).
({double width, double height}) computeThemeAnticipationHeroSize({
  required double maxWidth,
  required double maxHeight,
  double cellAspect = AppConstants.kThemeSelectedCardAspectRatio,
}) {
  final gap = maxWidth > 520
      ? kGenerationWaitAnticipationCellGap
      : kGenerationWaitAnticipationCellGap - 2;
  final imageMaxH = math.max(
    160.0,
    maxHeight - kGenerationWaitAnticipationLabelOverhead,
  );
  final cellMaxW = math.max(100.0, (maxWidth - gap) / 2);

  final cell = fitGenerationWaitAspectInBox(
    maxWidth: cellMaxW,
    maxHeight: imageMaxH,
    aspect: cellAspect,
  );

  return (
    width: cell.width * 2 + gap,
    height: cell.height + kGenerationWaitAnticipationLabelOverhead,
  );
}

/// Sizes the single-frame cinematic hero during pipeline previews.
({double width, double height}) computeGenerationWaitCinematicHeroSize({
  required double maxWidth,
  required double maxHeight,
  double aspect = AppConstants.kBeholdSingleResultDefaultAspectRatio,
}) {
  return fitGenerationWaitAspectInBox(
    maxWidth: maxWidth,
    maxHeight: math.max(180.0, maxHeight),
    aspect: aspect,
  );
}
