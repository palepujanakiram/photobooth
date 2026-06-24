import 'dart:math' as math;

import 'photo_generate_viewmodel.dart';
import '../../utils/app_strings.dart';

/// Scripted status lines when the server has not sent an update yet.
const List<String> kGenerationWaitRotatingCopy = [
  'Removing the background…',
  'Applying your style…',
  'Balancing light and color…',
  'Almost there — great portraits take a moment',
  'Polishing the details…',
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
