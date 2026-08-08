/// Pure helpers for HDMI capture-card + Canon Live View pose UX.
///
/// Classic POSE uses UVC for the live feed and the Pi sidecar for the still.
/// Countdown must not start until LV is held and HDMI has left the body status
/// LCD; the preview must stay masked while gphoto drops LV for the still.
library;

/// Whether HDMI/UVC Classic may auto-start the pose countdown.
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
