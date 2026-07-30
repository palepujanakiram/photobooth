import '../../utils/app_device_type.dart';

/// Kiosk tablets/TVs: try the UVC plugin before CameraX for USB webcams.
///
/// CameraX external cameras on Android TV often hang on [takePicture] / stream
/// grab; the dedicated UVC path is more reliable when a device is attached.
bool kioskShouldTryUvcBeforeCameraX(AppDeviceType? deviceType) {
  return deviceType == AppDeviceType.androidTv ||
      deviceType == AppDeviceType.androidTablet;
}
