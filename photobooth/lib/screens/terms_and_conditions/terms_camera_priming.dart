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

  // Direct Canon USB: show the system allow dialog before CAMERA / FCM compete.
  if (ensureCanonUsbPermission != null) {
    await ensureCanonUsbPermission();
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

/// Process-level memo of a Terms priming pass that reached [TermsCameraPrimingPhase.ready].
///
/// Terms is re-entered once per guest, but a USB grant and an open PTP session
/// outlive the screen. Without this, every guest replayed the full warm-up —
/// including its 20 s poll loop and the "Allow USB access…" banner — for a
/// camera that was already connected.
abstract final class TermsCanonPrimingMemo {
  static bool _primed = false;

  /// True once any priming pass in this process finished ready.
  static bool get isPrimed => _primed;

  static void markPrimed() => _primed = true;

  /// Forces the next Terms visit through a full priming pass (retry, tests).
  static void reset() => _primed = false;
}

/// Whether Terms may jump straight to ready instead of re-priming.
///
/// [probeStillReady] is the live check — a body unplugged between guests must
/// fall through to a full pass, so the memo alone is never enough.
Future<bool> canSkipTermsPrimingOnReentry({
  required bool primedBefore,
  required Future<bool> Function() probeStillReady,
}) async {
  if (!primedBefore) return false;
  try {
    return await probeStillReady();
  } on Object {
    return false;
  }
}

/// Whether the detecting banner should name the Canon USB grant.
///
/// The hint is only honest while the grant is actually missing: a booth that
/// was allowed on a previous guest never sees the system dialog again, so the
/// generic "Detecting cameras…" wording is the truthful one.
bool shouldShowCanonUsbPrimingHint({
  required bool isCanonUsbBooth,
  required bool permissionPending,
}) =>
    isCanonUsbBooth && permissionPending;
