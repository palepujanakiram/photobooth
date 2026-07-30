import '../../utils/app_device_type.dart';
import '../../utils/constants.dart';
import '../../utils/uvc_capture_config.dart';

/// Kiosk tablets/TVs: try the UVC plugin before CameraX for USB webcams.
///
/// CameraX external cameras on Android TV often hang on [takePicture] / stream
/// grab; the dedicated UVC path is more reliable when a device is attached.
bool kioskShouldTryUvcBeforeCameraX(AppDeviceType? deviceType) {
  return deviceType == AppDeviceType.androidTv ||
      deviceType == AppDeviceType.androidTablet;
}

/// Whether POSE may adopt Terms CameraX prewarm on first frame (phones only).
bool shouldAdoptTermsPrewarmOnPoseInit(AppDeviceType? deviceType) {
  return !kioskShouldTryUvcBeforeCameraX(deviceType);
}

/// UVC on kiosks already delivers a JPEG from the plugin — skip decode/re-encode.
bool shouldSkipUvcNormalizeOnKiosk(AppDeviceType? deviceType) {
  return kioskShouldTryUvcBeforeCameraX(deviceType);
}

/// Terms CameraX prewarm grabs USB before POSE; kiosks open UVC on POSE instead.
bool shouldSkipTermsCameraPrewarm(AppDeviceType? deviceType) {
  return kioskShouldTryUvcBeforeCameraX(deviceType);
}

/// UVC open budget on POSE entry — kiosks need the full native initialize window.
Duration uvcPoseEntryOpenTimeout(AppDeviceType? deviceType) {
  if (kioskShouldTryUvcBeforeCameraX(deviceType)) {
    return UvcCaptureConfig.openTimeout + const Duration(seconds: 4);
  }
  return UvcCaptureConfig.quickOpenTimeout;
}

/// Defer JPEG encode / face detection until Continue on memory-constrained kiosks.
bool shouldDeferUploadPrepUntilContinue({
  required AppDeviceType? deviceType,
  required String? cameraId,
}) {
  if (!UvcCaptureConfig.deferUploadPrepUntilContinue) return false;
  if (cameraId?.startsWith('uvc:') == true) return true;
  if (AppConstants.kLowMemoryKioskMode) return true;
  return kioskShouldTryUvcBeforeCameraX(deviceType);
}

/// Skip on-device ML Kit face count during upload prep on kiosks (server preprocess).
bool shouldSkipClientFaceDetectionForUpload({
  required AppDeviceType? deviceType,
  required String? cameraId,
}) {
  if (cameraId?.startsWith('uvc:') == true) return true;
  if (AppConstants.kLowMemoryKioskMode) return true;
  return kioskShouldTryUvcBeforeCameraX(deviceType);
}
