import 'dart:async';

/// Whether Classic 4-shot should resume the next pose before encode/scrub/Surprise.
class ClassicStripAcceptPlan {
  const ClassicStripAcceptPlan({
    required this.resumePreviewBeforeHeavyWork,
    required this.kickSurpriseMeAfterResume,
    required this.finishStrip,
  });

  /// True when more poses remain — remount must win over Gemini / Surprise Me.
  final bool resumePreviewBeforeHeavyWork;

  /// Kick Surprise Me only after shot 1 and only once preview is healthy again.
  final bool kickSurpriseMeAfterResume;

  /// Last shot — navigate to looks (no remount).
  final bool finishStrip;
}

/// Plan the post-accept work for Classic 4-shot after [acceptedCountAfterAdd].
ClassicStripAcceptPlan planClassicStripAccept({
  required int acceptedCountAfterAdd,
  required int total,
}) {
  final more = acceptedCountAfterAdd > 0 && acceptedCountAfterAdd < total;
  return ClassicStripAcceptPlan(
    resumePreviewBeforeHeavyWork: more,
    kickSurpriseMeAfterResume: more && acceptedCountAfterAdd == 1,
    finishStrip: acceptedCountAfterAdd >= total && total > 0,
  );
}

/// Completes [gate] exactly once (safe from resume + timeout races).
void completePoseReadyGate(Completer<void> gate) {
  if (!gate.isCompleted) {
    gate.complete();
  }
}
