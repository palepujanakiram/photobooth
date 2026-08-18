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
/// CameraX enumeration is preferred; UVC/HDMI capture cards and a healthy Pi
/// DSLR sidecar also count (Android TV often omits capture cards from
/// [availableCameras]).
bool termsHasUsableCaptureSource({
  required bool hasOpenableCameraX,
  required bool hasAttachedUvc,
  bool hasSidecarCamera = false,
}) {
  return hasOpenableCameraX || hasAttachedUvc || hasSidecarCamera;
}

/// Permission, enumeration, and optional prewarm kick-off for Terms idle time.
///
/// [probeAttachedUvc] / [probeSidecarHealthy] are optional fallbacks when
/// CameraX finds nothing (or enumeration throws), so Classic HDMI + Pi booths
/// are not blocked on Terms.
Future<TermsCameraPrimingResult> runTermsCameraPriming({
  required Future<bool> Function() ensurePermission,
  required Future<void> Function() preloadCameras,
  required Future<AppDeviceType?> Function() classifyDevice,
  required Future<void> Function(AppDeviceType? deviceType) startPrewarm,
  required bool Function(AppDeviceType? deviceType) hasOpenableCamera,
  required bool isCameraPlatform,
  Future<bool> Function()? probeAttachedUvc,
  Future<bool> Function()? probeSidecarHealthy,
  Future<bool> Function()? ensureCanonUsbPermission,
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

  if (ensureCanonUsbPermission != null) {
    await ensureCanonUsbPermission();
  }

  try {
    await preloadCameras();
  } on Object {
    if (await _fallbackCaptureReady(
      probeAttachedUvc: probeAttachedUvc,
      probeSidecarHealthy: probeSidecarHealthy,
    )) {
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
    var uvcOk = false;
    var sidecarOk = false;
    if (!cameraXOk) {
      uvcOk = await _probeOrFalse(probeAttachedUvc);
      if (!uvcOk) {
        sidecarOk = await _probeOrFalse(probeSidecarHealthy);
      }
    }
    if (!termsHasUsableCaptureSource(
      hasOpenableCameraX: cameraXOk,
      hasAttachedUvc: uvcOk,
      hasSidecarCamera: sidecarOk,
    )) {
      return const TermsCameraPrimingResult(TermsCameraPrimingPhase.noneFound);
    }
    // Skip CameraX prewarm when only UVC/sidecar is available — POSE opens them.
    if (cameraXOk) {
      await startPrewarm(deviceType);
    }
    return const TermsCameraPrimingResult(TermsCameraPrimingPhase.ready);
  } on Object {
    if (await _fallbackCaptureReady(
      probeAttachedUvc: probeAttachedUvc,
      probeSidecarHealthy: probeSidecarHealthy,
    )) {
      return const TermsCameraPrimingResult(TermsCameraPrimingPhase.ready);
    }
    return const TermsCameraPrimingResult(TermsCameraPrimingPhase.failed);
  }
}

Future<bool> _fallbackCaptureReady({
  Future<bool> Function()? probeAttachedUvc,
  Future<bool> Function()? probeSidecarHealthy,
}) async {
  if (await _probeOrFalse(probeAttachedUvc)) return true;
  return _probeOrFalse(probeSidecarHealthy);
}

Future<bool> _probeOrFalse(Future<bool> Function()? probe) async {
  if (probe == null) return false;
  try {
    return await probe();
  } on Object {
    return false;
  }
}
