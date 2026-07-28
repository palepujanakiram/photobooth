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

/// Permission, enumeration, and optional prewarm kick-off for Terms idle time.
Future<TermsCameraPrimingResult> runTermsCameraPriming({
  required Future<bool> Function() ensurePermission,
  required Future<void> Function() preloadCameras,
  required Future<AppDeviceType?> Function() classifyDevice,
  required Future<void> Function(AppDeviceType? deviceType) startPrewarm,
  required bool Function(AppDeviceType? deviceType) hasOpenableCamera,
  required bool isCameraPlatform,
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
    AppDeviceType? deviceType;
    try {
      deviceType = await classifyDevice();
    } catch (_) {
      // POSE will classify again if this fails.
    }
    if (!hasOpenableCamera(deviceType)) {
      return const TermsCameraPrimingResult(TermsCameraPrimingPhase.noneFound);
    }
    await startPrewarm(deviceType);
    return const TermsCameraPrimingResult(TermsCameraPrimingPhase.ready);
  } on Object {
    return const TermsCameraPrimingResult(TermsCameraPrimingPhase.failed);
  }
}
