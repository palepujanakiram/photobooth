/// Linear Classic 1-shot POSE machine — one still → looks, never auto-loops.
///
/// Designed so USB/UVC notify storms, warmup, and shutter interrupts cannot
/// restart a second countdown after the first attempt has begun.
enum ClassicOneShotPhase {
  /// Live preview; may auto-start the single countdown once.
  idle,

  /// Countdown running.
  counting,

  /// Shutter / normalize in progress.
  capturing,

  /// Still on the ViewModel; accepting → looks.
  captured,

  /// Encoding / navigating to look picker.
  finishing,

  /// Left POSE (or disposed).
  done,

  /// Attempt failed; only an explicit guest Capture may retry.
  needsGuest,
}

enum ClassicOneShotEvent {
  /// Camera became ready for the first auto-start.
  cameraReady,

  /// Guest tapped Capture / shutter (explicit only).
  guestCapture,

  /// Countdown finished and shutter started.
  shutterStarted,

  /// A still is on the ViewModel.
  stillReady,

  /// Countdown/capture produced no still.
  captureFailed,

  /// Accept → looks navigation started.
  finishStarted,

  /// Navigation completed / screen tearing down.
  finished,

  /// Guest retake cleared the review still (back to needsGuest).
  guestRetake,
}

/// Whether [phase] may begin a countdown (auto or guest).
bool classicOneShotMayStartCountdown(ClassicOneShotPhase phase) {
  return phase == ClassicOneShotPhase.idle ||
      phase == ClassicOneShotPhase.needsGuest;
}

/// Whether UVC button / preview-interrupt may act as guest Capture.
bool classicOneShotMayAcceptExternalShutter(ClassicOneShotPhase phase) {
  return classicOneShotMayStartCountdown(phase);
}

/// Whether VM/UVC listeners may drive any capture work.
bool classicOneShotBlocksAutoAdvance(ClassicOneShotPhase phase) {
  return phase != ClassicOneShotPhase.idle;
}

/// Pure transition. Returns null when [event] is ignored in [phase].
ClassicOneShotPhase? classicOneShotTransition({
  required ClassicOneShotPhase phase,
  required ClassicOneShotEvent event,
}) {
  switch (event) {
    case ClassicOneShotEvent.cameraReady:
      if (phase == ClassicOneShotPhase.idle) {
        return ClassicOneShotPhase.counting;
      }
      return null;
    case ClassicOneShotEvent.guestCapture:
      if (classicOneShotMayStartCountdown(phase)) {
        return ClassicOneShotPhase.counting;
      }
      return null;
    case ClassicOneShotEvent.shutterStarted:
      if (phase == ClassicOneShotPhase.counting) {
        return ClassicOneShotPhase.capturing;
      }
      return null;
    case ClassicOneShotEvent.stillReady:
      if (phase == ClassicOneShotPhase.counting ||
          phase == ClassicOneShotPhase.capturing) {
        return ClassicOneShotPhase.captured;
      }
      return null;
    case ClassicOneShotEvent.captureFailed:
      if (phase == ClassicOneShotPhase.counting ||
          phase == ClassicOneShotPhase.capturing ||
          phase == ClassicOneShotPhase.captured ||
          phase == ClassicOneShotPhase.finishing) {
        return ClassicOneShotPhase.needsGuest;
      }
      return null;
    case ClassicOneShotEvent.finishStarted:
      if (phase == ClassicOneShotPhase.captured) {
        return ClassicOneShotPhase.finishing;
      }
      return null;
    case ClassicOneShotEvent.finished:
      if (phase == ClassicOneShotPhase.finishing ||
          phase == ClassicOneShotPhase.captured) {
        return ClassicOneShotPhase.done;
      }
      return null;
    case ClassicOneShotEvent.guestRetake:
      if (phase == ClassicOneShotPhase.captured ||
          phase == ClassicOneShotPhase.finishing) {
        return ClassicOneShotPhase.needsGuest;
      }
      return null;
  }
}
