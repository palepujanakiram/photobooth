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
/// Masks during the last countdown tick, the post-countdown shutter arm gap,
/// and the full still download — when LV drops, HDMI often shows Quick Control.
bool uvcShouldMaskHdmiDuringStill({
  required bool hasCapturedPhoto,
  required bool isCapturing,
  required bool captureInFlight,
  required bool hdmiStillMaskArmed,
  required bool isCountingDown,
  int? countdownValue,
}) {
  if (hasCapturedPhoto) return false;
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
