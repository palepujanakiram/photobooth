import '../../utils/app_device_type.dart';

/// Camera preparation phase while the guest reads Terms.
enum TermsCameraPrimingPhase {
  /// Web / desktop — no native camera gate on Terms.
  skipped,

  /// Permission request + enumeration in progress.
  detecting,

  /// Enumeration and live-camera prewarm finished — Continue may proceed.
  ready,

  /// User denied camera permission.
  permissionDenied,

  /// Enumeration returned no usable cameras.
  noneFound,

  /// Unexpected failure during priming.
  failed,
}

/// Outcome of [runTermsCameraPriming].
class TermsCameraPrimingResult {
  const TermsCameraPrimingResult(this.phase);

  final TermsCameraPrimingPhase phase;

  /// Camera-only continue gate (upload alternatives ignored).
  bool get allowsContinue =>
      termsCameraPrimingAllowsContinue(phase: phase);
}

/// Whether Terms Continue may proceed for [phase].
///
/// When [photoUploadAllowed] is true, camera is optional: guests may continue
/// after noneFound / permissionDenied / failed and use Gallery or Phone QR.
bool termsCameraPrimingAllowsContinue({
  required TermsCameraPrimingPhase phase,
  bool photoUploadAllowed = false,
}) {
  if (phase == TermsCameraPrimingPhase.skipped ||
      phase == TermsCameraPrimingPhase.ready) {
    return true;
  }
  if (!photoUploadAllowed) return false;
  return phase == TermsCameraPrimingPhase.noneFound ||
      phase == TermsCameraPrimingPhase.permissionDenied ||
      phase == TermsCameraPrimingPhase.failed;
}

/// True when Terms may treat the booth as camera-ready.
///
/// CameraX enumeration is preferred; UVC/HDMI capture cards often never appear
/// in [availableCameras] on Android TV — an attached UVC webcam still counts.
bool termsHasUsableCaptureSource({
  required bool hasOpenableCameraX,
  required bool hasAttachedUvc,
}) {
  return hasOpenableCameraX || hasAttachedUvc;
}

/// Permission, enumeration, and optional prewarm kick-off for Terms idle time.
///
/// [probeAttachedUvc] is optional; when CameraX finds nothing (or enumeration
/// throws), a successful UVC probe still returns [TermsCameraPrimingPhase.ready]
/// so Classic HDMI booths are not blocked on Terms.
Future<TermsCameraPrimingResult> runTermsCameraPriming({
  required Future<bool> Function() ensurePermission,
  required Future<void> Function() preloadCameras,
  required Future<AppDeviceType?> Function() classifyDevice,
  required Future<void> Function(AppDeviceType? deviceType) startPrewarm,
  required bool Function(AppDeviceType? deviceType) hasOpenableCamera,
  required bool isCameraPlatform,
  Future<bool> Function()? probeAttachedUvc,
}) async {
  if (!isCameraPlatform) {
    return const TermsCameraPrimingResult(TermsCameraPrimingPhase.skipped);
  }

  final granted = await ensurePermission();
  if (!granted) {
    return const TermsCameraPrimingResult(
      TermsCameraPrimingPhase.permissionDenied,
    );
  }

  try {
    await preloadCameras();
  } on Object {
    final uvcOk = await _probeUvcOrFalse(probeAttachedUvc);
    if (uvcOk) {
      return const TermsCameraPrimingResult(TermsCameraPrimingPhase.ready);
    }
    return const TermsCameraPrimingResult(TermsCameraPrimingPhase.failed);
  }

  try {
    AppDeviceType? deviceType;
    try {
      deviceType = await classifyDevice();
    } catch (_) {
      // POSE will classify again if this fails.
    }
    final cameraXOk = hasOpenableCamera(deviceType);
    if (!termsHasUsableCaptureSource(
      hasOpenableCameraX: cameraXOk,
      hasAttachedUvc: cameraXOk
          ? false
          : await _probeUvcOrFalse(probeAttachedUvc),
    )) {
      return const TermsCameraPrimingResult(TermsCameraPrimingPhase.noneFound);
    }
    // Skip CameraX prewarm when only UVC is available — POSE opens UVC.
    if (cameraXOk) {
      await startPrewarm(deviceType);
    }
    return const TermsCameraPrimingResult(TermsCameraPrimingPhase.ready);
  } on Object {
    final uvcOk = await _probeUvcOrFalse(probeAttachedUvc);
    if (uvcOk) {
      return const TermsCameraPrimingResult(TermsCameraPrimingPhase.ready);
    }
    return const TermsCameraPrimingResult(TermsCameraPrimingPhase.failed);
  }
}

Future<bool> _probeUvcOrFalse(Future<bool> Function()? probe) async {
  if (probe == null) return false;
  try {
    return await probe();
  } on Object {
    return false;
  }
}
