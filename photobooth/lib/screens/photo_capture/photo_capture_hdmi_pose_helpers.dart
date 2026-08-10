/// Pure helpers for HDMI capture-card + Canon Live View pose UX.
///
/// Classic POSE uses UVC for the live feed and the Pi sidecar for the still.
/// Countdown must not start until LV is held and HDMI has left the body status
/// LCD; the preview must stay masked while gphoto drops LV for the still.
library;

import '../../utils/app_strings.dart';

/// Whether HDMI/UVC Classic may auto-start the pose countdown.
///
/// Do not pass [hdmiStillMaskArmed] as [captureInFlight]: the mask is armed
/// from countdown finished *before* shutter, and folding it into readiness
/// aborts the still (`hdmi_mask_armed` with no Pi `capture_begin`).
bool uvcHdmiPoseReadyForCountdown({
  required bool uvcControllerReady,
  required bool captureInFlight,
  required bool previewWarmupActive,
  required bool sidecarConfigured,
  required bool canonLvHolding,
}) {
  if (!uvcControllerReady || captureInFlight || previewWarmupActive) {
    return false;
  }
  // Without a sidecar there is no Canon LV to hold — plain UVC webcam is enough.
  if (sidecarConfigured && !canonLvHolding) return false;
  return true;
}

/// Whether the UVC preview card should hide HDMI (Canon status / Q menu).
///
/// For plain UVC/CameraX stills, masks during the last countdown tick, the
/// post-countdown shutter arm gap, and the full still download — when LV
/// drops, HDMI often shows Quick Control.
///
/// When [keepHdmiLiveForSidecarStill] is true (Pi DSLR owns the still), leave
/// HDMI/UVC live so guests never see a black "Setting up camera…" card while
/// prepareStill / capture runs in the background.
bool uvcShouldMaskHdmiDuringStill({
  required bool hasCapturedPhoto,
  required bool isCapturing,
  required bool captureInFlight,
  required bool hdmiStillMaskArmed,
  required bool isCountingDown,
  int? countdownValue,
  bool keepHdmiLiveForSidecarStill = false,
}) {
  if (hasCapturedPhoto) return false;
  if (keepHdmiLiveForSidecarStill) return false;
  if (isCapturing || captureInFlight || hdmiStillMaskArmed) return true;
  if (isCountingDown && countdownValue != null && countdownValue <= 1) {
    return true;
  }
  return false;
}

/// Guest-facing copy while the pose preview is masked for a still.
///
/// Sidecar Classic fires LV/movie exit clicks before the real shutter — phase
/// the copy so the first slap is "Setting up camera…" and the shutter is
/// "Say cheese!". Plain UVC/CameraX keeps "Capturing…".
String captureStillInProgressLabel({
  required bool usesSidecarDslr,
  bool preparingCamera = false,
  bool isCapturing = false,
}) {
  if (!usesSidecarDslr) return AppStrings.captureCapturingPhoto;
  if (isCapturing) return AppStrings.captureSayCheese;
  if (preparingCamera) return AppStrings.captureSettingUpCamera;
  return AppStrings.captureSayCheese;
}

/// Whether countdown [canStart] may stay true after sidecar prepare-still.
///
/// [prepareStill] intentionally drops Canon LV. Requiring [canonLvHolding]
/// (via full pose-ready) after that aborts the shutter and leaves the UI on
/// "Setting up camera…" forever.
bool uvcHdmiPoseCountdownCanContinue({
  required bool uvcControllerReady,
  required bool captureInFlight,
  required bool hasCapturedPhoto,
  required bool poseReadyForCountdown,
  required bool sidecarStillPrepStarted,
}) {
  if (!uvcControllerReady || captureInFlight || hasCapturedPhoto) {
    return false;
  }
  if (sidecarStillPrepStarted) return true;
  return poseReadyForCountdown;
}

/// Whether a sidecar still may fire right now.
///
/// Before prepare-still: LV must be held. After prepare / mask arm: LV is
/// expected to be down — blocking on [canonLvHolding] deadlocks shot 2+.
bool uvcHdmiPoseMayFireSidecarStill({
  required bool sidecarConfigured,
  required bool canonLvHolding,
  required bool sidecarStillPrepStarted,
}) {
  if (!sidecarConfigured) return true;
  if (sidecarStillPrepStarted) return true;
  return canonLvHolding;
}
