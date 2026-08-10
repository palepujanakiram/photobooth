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
///
/// Classic 4-shot: shot 1 uses the full window; shots 2–4 use the shorter
/// follow-on timer ([acceptedShotCount] ≥ 1).
int captureCountdownSecondsForMode({
  required bool isFlashbackMultiShot,
  int acceptedShotCount = 0,
}) {
  if (!isFlashbackMultiShot) return AppConstants.kCaptureCountdownSeconds;
  if (acceptedShotCount >= 1) {
    return AppConstants.kFlashbackFollowOnCountdownSeconds;
  }
  return AppConstants.kFlashbackCaptureCountdownSeconds;
}

/// Countdown step at which Classic + Pi should start [prepareStill].
///
/// Shot 1: mid-countdown ([kFlashbackSidecarStillPrepareAtSecond]).
/// Shots 2–4: as soon as the countdown starts ([countdownSeconds]) so LV exit
/// has the full pose window and the shutter is not blocked after zero.
int flashbackSidecarStillPrepareAtSecond({
  required int acceptedShotCount,
  int? countdownSeconds,
}) {
  if (acceptedShotCount >= 1) {
    return countdownSeconds ??
        AppConstants.kFlashbackFollowOnCountdownSeconds;
  }
  return AppConstants.kFlashbackSidecarStillPrepareAtSecond;
}

/// Review-hold length before auto-accept for the still just taken.
///
/// [acceptedShotCountBeforeThis] is strip length *before* accepting this still
/// (0 while reviewing shot 1).
Duration flashbackShotReviewHoldDuration({
  required int acceptedShotCountBeforeThis,
  required int total,
}) {
  if (total == 1) return const Duration(milliseconds: 600);
  if (acceptedShotCountBeforeThis >= 1) {
    return AppConstants.kFlashbackFollowOnShotReviewDuration;
  }
  return AppConstants.kFlashbackShotReviewDuration;
}

/// Mid-strip status while waiting for LV / HDMI warmup (not counting down).
bool shouldShowClassicBetweenShotReadyBanner({
  required bool isFourShot,
  required int acceptedCount,
  required int total,
  required bool hasCapturedPhoto,
  required bool isCountingDown,
  required bool isCapturing,
  required bool cameraReadyForCapture,
  required bool acceptingShot,
}) {
  if (!isFourShot || hasCapturedPhoto || isCountingDown || isCapturing) {
    return false;
  }
  if (acceptedCount <= 0 || acceptedCount >= total || total <= 0) return false;
  return acceptingShot || !cameraReadyForCapture;
}

/// Soft-fail when mask/prep is stuck with no shutter after countdown ends.
bool shouldSoftFailHdmiMaskStall({
  required bool maskArmedOrPrep,
  required bool captureInFlight,
  required bool isCapturing,
  required bool isCountingDown,
}) {
  if (!maskArmedOrPrep || captureInFlight || isCapturing) return false;
  if (isCountingDown) return false;
  return true;
}
