import 'generation_wait_helpers.dart';
import 'photo_generate_viewmodel.dart';

/// Scripted face-analysis lines shown during act 1 (one per second).
const List<String> kGenerationWaitFaceScanLines = [
  'Face detected',
  'Hair detected',
  'Lighting matched',
  'Pose analyzed',
  'Expressions preserved',
  'Identity locked',
];

/// Dynamic activity quotes — rotate every 5 seconds (no percentages).
const List<String> kGenerationWaitDynamicQuotes = [
  'Crafting your cinematic portrait…',
  'Matching premium fashion…',
  'Building studio lighting…',
  'Adding luxury textures…',
  'Refining facial details…',
  'Almost there…',
];

/// Peripheral marketing lines for mall spectators.
const List<String> kGenerationWaitMarketingTaglines = [
  'Try 40+ AI worlds.',
  'New themes added every month.',
  'Your face. Reimagined.',
  'Hollywood-quality AI portraits.',
  'Printed in seconds.',
  'Identity preserved with AI.',
];

/// Premium fact cards (title + body) for the wait footer.
const List<({String title, String body})> kGenerationWaitFactCards = [
  (
    title: 'Identity locked',
    body: 'Your face is preserved exactly — not a random AI face.',
  ),
  (
    title: 'Luxury costumes',
    body: 'Every outfit is uniquely rendered for your portrait.',
  ),
  (
    title: 'Privacy first',
    body: 'Your session photos are handled securely and privately.',
  ),
  (
    title: 'Studio lighting',
    body: 'Hollywood-quality portrait lighting on every theme.',
  ),
];

/// Five-act story chapter headlines (stretch to real runtime).
const List<String> kGenerationWaitActHeadlines = [
  'AI is studying your portrait',
  'Preparing your AI look',
  'Building the world',
  'Adding premium details',
  'Almost ready…',
];

enum GenerationWaitBeatState { pending, active, done }

class GenerationWaitRewardBeat {
  const GenerationWaitRewardBeat({
    required this.label,
    required this.state,
  });

  final String label;
  final GenerationWaitBeatState state;
}

int generationWaitActIndex(
  PhotoGenerateViewModel vm,
  GenerationWaitPresentation presentation,
) {
  if (generationWaitPolishingStarted(vm) || presentation.showPolishingOverlay) {
    return 4;
  }
  if (previewUrlForStage(vm, 'ai_generation') != null) {
    return presentation.showPolishingOverlay ? 4 : 3;
  }
  if (previewUrlForStage(vm, 'background_removal') != null) return 2;
  if (previewUrlForStage(vm, 'preprocessing') != null) return 1;

  final elapsed = vm.elapsedSeconds;
  if (elapsed >= 45) return 4;
  if (elapsed >= 30) return 3;
  if (elapsed >= 15) return 2;
  if (elapsed >= 5) return 1;
  return 0;
}

String generationWaitActHeadline(
  PhotoGenerateViewModel vm,
  GenerationWaitPresentation presentation,
) {
  final index = generationWaitActIndex(vm, presentation);
  return kGenerationWaitActHeadlines[index.clamp(0, kGenerationWaitActHeadlines.length - 1)];
}

String generationWaitDynamicQuote(int elapsedSeconds) {
  if (elapsedSeconds <= 0) return kGenerationWaitDynamicQuotes.first;
  final index = (elapsedSeconds ~/ 5) % kGenerationWaitDynamicQuotes.length;
  return kGenerationWaitDynamicQuotes[index];
}

String generationWaitMarketingTagline(int elapsedSeconds) {
  if (elapsedSeconds <= 0) return kGenerationWaitMarketingTaglines.first;
  final index = (elapsedSeconds ~/ 6) % kGenerationWaitMarketingTaglines.length;
  return kGenerationWaitMarketingTaglines[index];
}

({String title, String body}) generationWaitFactCard(int elapsedSeconds) {
  if (elapsedSeconds <= 0) return kGenerationWaitFactCards.first;
  final index = (elapsedSeconds ~/ 10) % kGenerationWaitFactCards.length;
  return kGenerationWaitFactCards[index];
}

int generationWaitFaceScanCompletedCount(int elapsedSeconds) {
  if (elapsedSeconds <= 0) return 0;
  return elapsedSeconds.clamp(0, kGenerationWaitFaceScanLines.length);
}

bool generationWaitShowFaceScanChecklist(
  PhotoGenerateViewModel vm,
  GenerationWaitPresentation presentation,
) {
  if (!vm.isOperationInProgress) return false;
  if (generationWaitHasPipelinePreviews(vm)) return false;
  return generationWaitActIndex(vm, presentation) <= 1;
}

List<GenerationWaitRewardBeat> resolveGenerationWaitRewardChecklist(
  PhotoGenerateViewModel vm,
  GenerationWaitPresentation presentation,
) {
  const labels = [
    'Identity',
    'Lighting',
    'Costume',
    'Background',
    'Effects',
    'Final polish',
  ];

  final preprocessDone = previewUrlForStage(vm, 'preprocessing') != null;
  final bgDone = previewUrlForStage(vm, 'background_removal') != null;
  final aiDone = previewUrlForStage(vm, 'ai_generation') != null;
  final polishStarted = generationWaitPolishingStarted(vm);
  final polishFinishing = presentation.showPolishingOverlay &&
      polishStarted;
  final elapsed = vm.elapsedSeconds;

  final doneFlags = <bool>[
    preprocessDone || elapsed >= 8,
    bgDone || elapsed >= 16,
    aiDone || elapsed >= 26,
    aiDone || elapsed >= 34,
    polishStarted || elapsed >= 42,
    polishFinishing || (aiDone && elapsed >= 50),
  ];

  final beats = <GenerationWaitRewardBeat>[];
  var foundActive = false;
  for (var i = 0; i < labels.length; i++) {
    if (doneFlags[i]) {
      beats.add(GenerationWaitRewardBeat(
        label: labels[i],
        state: GenerationWaitBeatState.done,
      ));
    } else if (!foundActive) {
      foundActive = true;
      beats.add(GenerationWaitRewardBeat(
        label: labels[i],
        state: GenerationWaitBeatState.active,
      ));
    } else {
      beats.add(GenerationWaitRewardBeat(
        label: labels[i],
        state: GenerationWaitBeatState.pending,
      ));
    }
  }
  return beats;
}
