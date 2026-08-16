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
/// Classic 1-shot and 4-shot use a 10s pose window for every shutter.
int captureCountdownSecondsForMode({
  required bool isFlashbackMultiShot,
  int acceptedShotCount = 0,
}) {
  if (!isFlashbackMultiShot) return AppConstants.kCaptureCountdownSeconds;
  // Follow-on shots use the same 10s window as shot 1.
  if (acceptedShotCount >= 1) {
    return AppConstants.kFlashbackFollowOnCountdownSeconds;
  }
  return AppConstants.kFlashbackCaptureCountdownSeconds;
}

/// Countdown step at which HDMI + Pi gphoto2 should start [prepareStill].
///
/// All Classic shots prepare mid-countdown so EVF stays up for most of the
/// 10s pose window, then tears down ~4s before shutter.
///
/// Not used when Pose is the Canon USB EVF stream — see
/// [shouldPrepareSidecarStillDuringCountdown].
int flashbackSidecarStillPrepareAtSecond({
  required int acceptedShotCount,
  int? countdownSeconds,
}) {
  // [acceptedShotCount] / [countdownSeconds] kept for call-site compatibility.
  return AppConstants.kFlashbackSidecarStillPrepareAtSecond;
}

/// Whether to tear down sidecar live view mid-countdown.
///
/// HDMI + Pi: yes — movie LV needs ~2–3s to exit so the shutter can land at 0.
/// Canon USB EVF pose: no — that live view is the guest preview. Stopping it
/// at countdown 4 freezes the frame. Capture still calls prepare-still
/// immediately before the shutter.
bool shouldPrepareSidecarStillDuringCountdown({
  required bool sidecarConfigured,
  required bool poseShowsSidecarLivePreview,
}) {
  if (!sidecarConfigured) return false;
  if (poseShowsSidecarLivePreview) return false;
  return true;
}

/// Review-hold length before auto-accept for the still just taken.
///
/// [acceptedShotCountBeforeThis] is strip length *before* accepting this still
/// (0 while reviewing shot 1). Mid-strip uses the 8s rearrange window; the
/// final still (and Classic 1-shot) use a short handoff to looks.
Duration flashbackShotReviewHoldDuration({
  required int acceptedShotCountBeforeThis,
  required int total,
}) {
  if (total <= 1) return const Duration(milliseconds: 600);
  final shotNumber = acceptedShotCountBeforeThis + 1;
  if (shotNumber >= total) {
    return AppConstants.kFlashbackLastShotReviewDuration;
  }
  return AppConstants.kFlashbackBetweenShotRearrangeDuration;
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
