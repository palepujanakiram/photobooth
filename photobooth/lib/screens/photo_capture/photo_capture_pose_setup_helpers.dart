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
/// Sidecar DSLR pose must skip CameraX too — even when the box is classified
/// as a phone. After shutter, USB re-enumeration used to call
/// [CaptureViewModel.resetAndInitializeCameras] and wipe the review still.
bool kioskShouldSkipCameraXWhenUvcUnavailable(
  AppDeviceType? deviceType, {
  bool sidecarConfigured = false,
}) {
  if (sidecarConfigured) return true;
  return kioskShouldTryUvcBeforeCameraX(deviceType);
}

/// Keep the POSE "Starting camera…" wait only while a UVC webcam is attached
/// or the sidecar can still serve HTTP. Otherwise the spinner never ends.
bool shouldKeepPoseStartingForExternalSource({
  required bool uvcWebcamAttached,
  required bool sidecarConfigured,
}) {
  return uvcWebcamAttached || sidecarConfigured;
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
