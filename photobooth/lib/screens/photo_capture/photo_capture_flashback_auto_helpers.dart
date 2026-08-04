import '../../utils/constants.dart';

/// Whether a Classic review-hold timer is already running (do not re-arm).
bool flashbackReviewHoldAlreadyScheduled({
  required bool timerActive,
  required bool hasDeadline,
}) {
  return timerActive || hasDeadline;
}

/// Whether Classic strip capture should auto-start the next pose countdown.
bool shouldAutoStartFlashbackCountdown({
  required bool isFlashbackMultiShot,
  required bool stripFinishing,
  required bool navigatingAway,
  required bool hasCapturedPhoto,
  required bool isCountingDown,
  required bool isCapturing,
  required int acceptedShotCount,
  required int multiShotTotal,
  required bool cameraReadyForCapture,
  bool isSingleShot = false,
  int singleShotCapturesStarted = 0,
  bool awaitGuestStart = false,
}) {
  if (awaitGuestStart) return false;
  if (!isFlashbackMultiShot || stripFinishing || navigatingAway) return false;
  if (hasCapturedPhoto || isCountingDown || isCapturing) return false;
  if (acceptedShotCount >= multiShotTotal || multiShotTotal <= 0) return false;
  // Classic 1-shot may only auto-fire the shutter once per live pose.
  if (isSingleShot && singleShotCapturesStarted >= 1) return false;
  return cameraReadyForCapture;
}

/// Whether Classic should schedule auto-accept of the just-taken review still.
bool shouldScheduleFlashbackAutoAccept({
  required bool isFlashbackMultiShot,
  required bool stripFinishing,
  required bool navigatingAway,
  required bool hasCapturedPhoto,
  required bool isCapturing,
  required bool autoAcceptAlreadyScheduled,
}) {
  if (!isFlashbackMultiShot || stripFinishing || navigatingAway) return false;
  if (!hasCapturedPhoto || isCapturing) return false;
  if (autoAcceptAlreadyScheduled) return false;
  return true;
}

/// Seconds remaining for a review-hold deadline (floor, never negative).
int flashbackReviewSecondsRemaining({
  required DateTime endsAt,
  DateTime? now,
}) {
  final left = endsAt.difference(now ?? DateTime.now()).inSeconds;
  if (left < 0) return 0;
  return left;
}

/// Pose countdown length for the active capture mode.
int captureCountdownSecondsForMode({required bool isFlashbackMultiShot}) {
  return isFlashbackMultiShot
      ? AppConstants.kFlashbackCaptureCountdownSeconds
      : AppConstants.kCaptureCountdownSeconds;
}
