import '../screens/photo_capture/photo_capture_viewmodel.dart';
import 'app_device_type.dart';

/// True when Terms/POSE enumerated at least one openable CameraX camera.
bool hasOpenableDeviceCaptureCamera({AppDeviceType? deviceType}) {
  return CaptureViewModel.hasOpenableCaptureCamera(deviceType: deviceType);
}

/// Prefer built-in / CameraX when the configured DSLR path cannot serve capture.
bool shouldPreferDeviceCameraOverDslr({
  required bool dslrPathCanServe,
  required bool hasOpenableDeviceCamera,
}) {
  return !dslrPathCanServe && hasOpenableDeviceCamera;
}
