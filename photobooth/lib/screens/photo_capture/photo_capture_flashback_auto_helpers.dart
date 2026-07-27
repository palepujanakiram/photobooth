import '../../utils/constants.dart';

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
}) {
  if (!isFlashbackMultiShot || stripFinishing || navigatingAway) return false;
  if (hasCapturedPhoto || isCountingDown || isCapturing) return false;
  if (acceptedShotCount >= multiShotTotal || multiShotTotal <= 0) return false;
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

/// Pose countdown length for the active capture mode.
int captureCountdownSecondsForMode({required bool isFlashbackMultiShot}) {
  return isFlashbackMultiShot
      ? AppConstants.kFlashbackCaptureCountdownSeconds
      : AppConstants.kCaptureCountdownSeconds;
}
