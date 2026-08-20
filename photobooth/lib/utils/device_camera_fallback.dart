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

/// Keep sidecar EVF only when the DSLR is actually usable — or when there is
/// no CameraX fallback (Direct USB warm-up / waiting for the body).
///
/// EDSDK `running` / HTTP listening alone is not enough: AI live-preview used
/// to commit to a blank EVF while Classic later recovered via health checks and
/// opened the tablet camera.
bool shouldCommitToSidecarPoseSession({
  required bool sidecarReadyOrHealthy,
  required bool hasOpenableDeviceCamera,
  required bool keepDirectWithoutDeviceFallback,
}) {
  if (sidecarReadyOrHealthy) return true;
  if (hasOpenableDeviceCamera) return false;
  return keepDirectWithoutDeviceFallback;
}
