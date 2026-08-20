import 'package:flutter/painting.dart';

import '../../utils/app_device_type.dart';
import '../../utils/constants.dart';
import '../../utils/uvc_capture_config.dart';

/// Prefer Pi USB MJPEG over HDMI→UVC for pose preview (lab / dart-define).
///
/// Production booths opt in via admin `cameraLivePreviewEnabled` (Classic + AI).
bool shouldForceSidecarLivePreview({required bool sidecarConfigured}) {
  return false;
}

/// Whether POSE should show Pi MJPEG instead of opening CameraX/UVC.
///
/// When admin **Show Pi live preview** is on (EDSDK or gphoto
/// `GET /camera/live` + `POST /camera/live-view`), Classic and AI both use the
/// DSLR EVF stream. Classic can also fall back to Pi if HDMI/UVC fails to open.
bool shouldUseSidecarPosePreview({
  required bool classicSession,
  required bool sidecarLivePreviewEnabled,
  required bool sidecarConfigured,
  bool classicSidecarFallback = false,
}) {
  if (!sidecarConfigured) return false;
  // Admin kiosk toggle — EDSDK MJPEG for Classic 1-shot / 4-shot and AI.
  if (sidecarLivePreviewEnabled) return true;
  // Classic: HDMI open failed → temporary Pi `/camera/live`.
  if (classicSession) return classicSidecarFallback;
  return shouldForceSidecarLivePreview(sidecarConfigured: sidecarConfigured);
}

/// Gallery / Phone QR on POSE — same [photoUploadAllowed] gate for AI + Classic.
///
/// Mid Classic 4-shot strip still hides uploads so a gallery pick cannot break
/// strip indexing / remount.
bool capturePhotoUploadActionsAllowed({
  required bool photoUploadAllowed,
  required bool classicFourShotInProgress,
}) {
  if (!photoUploadAllowed) return false;
  if (classicFourShotInProgress) return false;
  return true;
}

/// Kiosk tablets/TVs: try the UVC plugin before CameraX for USB webcams.
///
/// CameraX external cameras on Android TV often hang on [takePicture] / stream
/// grab; the dedicated UVC path is more reliable when a device is attached.
bool kioskShouldTryUvcBeforeCameraX(AppDeviceType? deviceType) {
  return deviceType == AppDeviceType.androidTv ||
      deviceType == AppDeviceType.androidTablet;
}

/// Kiosk TV/tablet boxes often have zero Camera2 cameras. Calling
/// [availableCameras] then makes CameraX retry until ANR.
///
/// Phones and any device that already enumerated a CameraX camera must not
/// skip — otherwise POSE waits on Canon localhost `:8791` instead of the
/// front camera. Sidecar EVF is used only when a Canon body is actually on USB
/// ([sidecarConfigured] after [sidecarConfiguredForExternalPose]).
bool kioskShouldSkipCameraXWhenUvcUnavailable(
  AppDeviceType? deviceType, {
  bool sidecarConfigured = false,
  bool preferDeviceCameraFallback = false,
  bool hasOpenableDeviceCamera = false,
}) {
  if (preferDeviceCameraFallback) return false;
  if (hasOpenableDeviceCamera) return false;
  if (!kioskShouldTryUvcBeforeCameraX(deviceType)) return false;
  return sidecarConfigured || kioskShouldTryUvcBeforeCameraX(deviceType);
}

/// Keep the POSE "Starting camera…" wait only while a UVC webcam is attached
/// or the sidecar can still serve HTTP. Otherwise the spinner never ends.
bool shouldKeepPoseStartingForExternalSource({
  required bool uvcWebcamAttached,
  required bool sidecarConfigured,
  bool preferDeviceCameraFallback = false,
}) {
  if (preferDeviceCameraFallback) return false;
  return uvcWebcamAttached || sidecarConfigured;
}

/// After HDMI/UVC cannot open, poll Canon EDSDK EVF when the sidecar is
/// configured (AI and Classic). HDMI remains preferred when a capture card
/// is actually attached.
bool shouldStartSidecarPreviewAfterUvcMiss({
  required bool sidecarConfigured,
}) {
  return sidecarConfigured;
}

/// Do not spend the UVC open budget when no capture card is attached.
bool shouldSkipUvcProbeForSidecarPose({
  required bool sidecarConfigured,
  required bool uvcWebcamAttached,
}) {
  return sidecarConfigured && !uvcWebcamAttached;
}

/// FotoZen after UVC miss with no DSLR/UVC: fall through to CameraX.
///
/// Classic continues the fuller recover path (sidecar poll / prefer-device).
/// FotoZen used to return here without marking prefer-device, so tablets hit
/// [kioskShouldSkipCameraXWhenUvcUnavailable] and never opened CameraX.
bool shouldFotoZenFallThroughToDeviceCameraAfterUvcMiss({
  required bool isClassic,
  required bool uvcAttached,
  required bool sidecarConfigured,
}) {
  return !isClassic && !uvcAttached && !sidecarConfigured;
}

/// HDMI settle waits for the capture card to leave the body LCD.
/// USB EVF MJPEG is already the pose preview — skip that pause.
bool shouldWaitHdmiSettleAfterCanonLv({
  required bool sidecarIsPosePreview,
}) {
  return !sidecarIsPosePreview;
}

/// Direct USB EDSDK is a live pose source only when a Canon body is on USB.
///
/// Android defaults to localhost `:8791` even on phones. Treating that as
/// "configured" made POSE wait for Canon instead of the front camera.
bool sidecarConfiguredForExternalPose({
  required bool sidecarConfigured,
  required bool isDirectConnection,
  required bool canonUsbPresent,
}) {
  if (!sidecarConfigured) return false;
  if (isDirectConnection) return canonUsbPresent;
  return true;
}

/// Direct USB: keep Pose on EDSDK EVF (do not fall through to HDMI/UVC/webcam).
///
/// Requires a configured sidecar endpoint **and** a Canon on USB. Flutter web
/// disables the localhost sidecar, so this is false and Pose opens
/// `getUserMedia` instead. iOS disables direct EDSDK the same way.
bool shouldKeepDirectSidecarPose({
  required bool isDirectConnection,
  required bool hasSidecarEndpoint,
  bool preferDeviceCameraFallback = false,
  bool canonUsbPresent = true,
}) {
  if (!isDirectConnection || !hasSidecarEndpoint) return false;
  if (preferDeviceCameraFallback) return false;
  if (!canonUsbPresent) return false;
  return true;
}

/// GSM omitted `cameraConnectionMode` and a leftover Pi host inferred Pi.
/// If that Pi is down and on-device EDSDK is running, use USB EVF.
///
/// Explicit backend `pi` is never overridden.
bool shouldSwitchInferredPiToDirect({
  required bool isPiConnection,
  required bool modeExplicit,
  required bool piListening,
  required bool nativeSidecarRunning,
}) {
  if (modeExplicit || !isPiConnection || piListening) return false;
  return nativeSidecarRunning;
}

/// Whether POSE may adopt Terms CameraX prewarm on first frame (phones only).
bool shouldAdoptTermsPrewarmOnPoseInit(AppDeviceType? deviceType) {
  return !kioskShouldTryUvcBeforeCameraX(deviceType);
}

/// Whether UVC stills may skip [ImageHelper.normalizeAndSaveCapturedPhoto].
///
/// Always false: many UVC/HDMI stacks write BGR-as-RGB JPEGs (greenish-blue
/// cast). Normalize applies [fixBgrChannelOrder] and must run on kiosks too.
bool shouldSkipUvcNormalizeOnKiosk(AppDeviceType? deviceType) {
  return false;
}

/// Terms CameraX prewarm grabs USB before POSE; kiosks open UVC on POSE instead.
bool shouldSkipTermsCameraPrewarm(AppDeviceType? deviceType) {
  return kioskShouldTryUvcBeforeCameraX(deviceType);
}

/// UVC open budget on POSE entry — kiosks need the full native initialize window.
Duration uvcPoseEntryOpenTimeout(AppDeviceType? deviceType) {
  if (kioskShouldTryUvcBeforeCameraX(deviceType)) {
    return UvcCaptureConfig.openTimeout + const Duration(seconds: 2);
  }
  return UvcCaptureConfig.quickOpenTimeout;
}

/// Review still fit. Sidecar live pose uses [BoxFit.cover]; letterbox contain
/// left a landscape Canon JPEG as a thin strip on a black portrait card.
BoxFit poseReviewStillBoxFit({required bool sidecarPosePreview}) {
  return sidecarPosePreview ? BoxFit.cover : BoxFit.contain;
}

/// Decode the full sidecar JPEG on review. [cacheWidth] on this Mini PC
/// made the still look soft; 1920 long-edge is safe without GPU downscale.
bool poseReviewStillSharpDisplay({
  required bool sidecarPosePreview,
  required AppDeviceType? deviceType,
}) {
  if (sidecarPosePreview) return true;
  return !kioskShouldTryUvcBeforeCameraX(deviceType);
}

/// Defer JPEG encode / face detection until Continue on memory-constrained kiosks.
bool shouldDeferUploadPrepUntilContinue({
  required AppDeviceType? deviceType,
  required String? cameraId,
}) {
  if (!UvcCaptureConfig.deferUploadPrepUntilContinue) return false;
  if (cameraId?.startsWith('uvc:') == true) return true;
  if (cameraId?.startsWith('sidecar:') == true) return true;
  if (AppConstants.kLowMemoryKioskMode) return true;
  return kioskShouldTryUvcBeforeCameraX(deviceType);
}

/// Skip on-device ML Kit face count during upload prep on kiosks (server preprocess).
bool shouldSkipClientFaceDetectionForUpload({
  required AppDeviceType? deviceType,
  required String? cameraId,
}) {
  if (cameraId?.startsWith('uvc:') == true) return true;
  if (cameraId?.startsWith('sidecar:') == true) return true;
  if (AppConstants.kLowMemoryKioskMode) return true;
  return kioskShouldTryUvcBeforeCameraX(deviceType);
}

/// CameraX is the live path — do not skip enumeration/open for sidecar EVF.
bool shouldSkipCameraXForSidecarEvf({
  required bool usesSidecarLivePreview,
  required bool preferDeviceCameraCapture,
}) {
  return usesSidecarLivePreview && !preferDeviceCameraCapture;
}

/// Whether POSE countdown/shutter may start for the active preview path.
///
/// Default Android sidecar config enables Pi/USB EVF, but phones without a
/// Canon body show CameraX. Waiting on sidecar preview-ready in that case
/// makes Capture taps no-op.
bool poseCaptureIsReady({
  required bool preferDeviceCameraCapture,
  required bool usesSidecarLivePreview,
  required bool sidecarPreviewReady,
  required bool cameraControllerInitialized,
  required bool isDesktopCaptureMode,
  required bool isLoadingCameras,
}) {
  if (isDesktopCaptureMode) return !isLoadingCameras;
  if (preferDeviceCameraCapture || cameraControllerInitialized) {
    return cameraControllerInitialized;
  }
  if (usesSidecarLivePreview) return sidecarPreviewReady;
  return false;
}
