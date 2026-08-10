// Pure helpers for POSE body phase when camera may be absent (upload-only).

/// Whether the capture screen should show the "Starting camera…" placeholder.
bool isCapturePreviewStarting({
  required bool hasCapturedPhoto,
  required bool isDesktopCaptureMode,
  required bool isLoadingCameras,
  required bool isInitializing,
  required bool isCapturing,
  required bool isUsingUvc,
  required bool uvcHoldLivePreviewClosed,
  required bool uvcInitializing,
  required bool uvcOpeningController,
  required bool uvcControllerReady,
  required bool camerasEmpty,
  required bool isReady,
  bool cameraSetupStalled = false,
  bool usesSidecarLivePreview = false,
  bool expectExternalCaptureSource = false,
}) {
  if (hasCapturedPhoto) return false;
  if (isCapturing) return false;
  if (uvcHoldLivePreviewClosed) return false;
  if (cameraSetupStalled) return false;
  if (usesSidecarLivePreview) return false;
  if (isDesktopCaptureMode) return isLoadingCameras;
  if (isLoadingCameras || isInitializing) return true;
  if (isUsingUvc) {
    if (uvcInitializing || uvcOpeningController) return true;
    return !uvcControllerReady;
  }
  // USB/HDMI or Pi still expected — keep starting UI while probes retry.
  if (expectExternalCaptureSource && camerasEmpty) return true;
  // Enumeration finished with nothing — show no-camera / upload UI, not spinner.
  if (camerasEmpty) return false;
  return !isReady;
}

/// Body content branch for the capture screen (non-desktop).
enum CaptureBodyPhase {
  starting,
  noCameras,
  error,
  live,
}

CaptureBodyPhase resolveCaptureBodyPhase({
  required bool isPreviewStarting,
  required bool camerasEmpty,
  required bool hasError,
  required bool isUsingUvc,
  required bool hasCapturedPhoto,
  bool isSelectingFromGallery = false,
  bool usesSidecarLivePreview = false,
  bool expectExternalCaptureSource = false,
}) {
  if (isPreviewStarting) return CaptureBodyPhase.starting;
  // Gallery / phone upload review must not fall back to the empty-camera screen.
  if (hasCapturedPhoto || isSelectingFromGallery) {
    return CaptureBodyPhase.live;
  }
  // Prefer upload / retry UI over fatal error when no camera was enumerated —
  // unless UVC/HDMI or Pi sidecar is still expected (Classic booth).
  if (camerasEmpty &&
      !isUsingUvc &&
      !usesSidecarLivePreview &&
      !expectExternalCaptureSource) {
    return CaptureBodyPhase.noCameras;
  }
  if (hasError &&
      !isUsingUvc &&
      !usesSidecarLivePreview &&
      !expectExternalCaptureSource) {
    return CaptureBodyPhase.error;
  }
  return CaptureBodyPhase.live;
}

/// Whether continuous UVC probing should run after CameraX found nothing.
bool shouldProbeUvcAfterNoCameraX({
  required bool photoUploadAllowed,
  required bool camerasEmpty,
  required bool uvcFeedHealthy,
  required bool cameraReady,
  bool forceUvcRetry = false,
}) {
  if (uvcFeedHealthy || cameraReady) return false;
  // Classic / HDMI booths: keep probing even when Gallery upload is enabled.
  if (forceUvcRetry && camerasEmpty) return true;
  // Upload path is available — do not keep opening UVC in the background.
  if (photoUploadAllowed && camerasEmpty) return false;
  return camerasEmpty;
}
