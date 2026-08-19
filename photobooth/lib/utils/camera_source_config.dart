import 'package:flutter/foundation.dart' show visibleForTesting;

/// Where the booth's stills come from.
///
/// Selected by configuration rather than detected, because on a kiosk the wrong
/// guess is worse than a required setting: a rig with both a DSLR and an HDMI
/// capture card attached is a normal booth, and only the operator knows which
/// one is meant to take the photo.
enum CameraSource {
  /// Built-in / CameraX camera. The default, and what every existing build uses.
  device,

  /// External USB webcam or HDMI capture card via the `uvccamera` plugin.
  uvc,

  /// Raspberry Pi `fotozen-sidecar` driving a DSLR over gphoto2.
  sidecar,

  /// DSLR driven directly over USB PTP from this device, with a native capture
  /// screen. No Pi involved.
  directPtp;

  /// True when stills come from a tethered DSLR rather than a video source.
  bool get isDslr => this == sidecar || this == directPtp;
}

/// Parses a configured source name; unknown values fall back to [fallback].
///
/// Tolerant on purpose: this value can arrive from remote kiosk settings, and a
/// typo there should leave the booth shooting on its default camera rather than
/// refusing to start an event.
CameraSource cameraSourceFromName(
  String? raw, {
  CameraSource fallback = CameraSource.device,
}) {
  switch (raw?.trim().toLowerCase().replaceAll('-', '_')) {
    case 'device':
    case 'camerax':
    case 'builtin':
    case 'built_in':
      return CameraSource.device;
    case 'uvc':
    case 'external':
    case 'hdmi':
      return CameraSource.uvc;
    case 'sidecar':
    case 'pi':
      return CameraSource.sidecar;
    case 'direct_ptp':
    case 'directptp':
    case 'ptp':
    case 'dslr':
      return CameraSource.directPtp;
    default:
      return fallback;
  }
}

/// Build-time override:
/// ```
/// --dart-define=CAMERA_SOURCE=direct_ptp
/// ```
///
/// Empty by default, so builds without it behave exactly as before. P5 of the
/// direct-PTP plan promotes this to per-kiosk config from zenai; this define
/// stays as the lab override, mirroring `CAMERA_SIDECAR_ENABLED`.
const String kCameraSourceDefine =
    String.fromEnvironment('CAMERA_SOURCE', defaultValue: '');

/// Camera source published by kiosk configuration, or null before settings load.
///
/// ZenAI owns this now (`Connection → Direct PTP (native USB, no EDSDK)` on the kiosk edit
/// screen). It is cached in a top-level variable rather than read from a provider because
/// [resolveCameraSource] is called from route builders and plain functions that have no
/// `BuildContext`, and because the answer must be identical everywhere in the process —
/// two call sites disagreeing about which POSE screen to open is the failure mode that
/// [buildCaptureScreen]'s own docstring describes.
CameraSource? _configuredCameraSource;

/// Publishes the source implied by kiosk settings. Null clears it.
///
/// Called when app settings load or change. Only [CameraConnectionMode.directPtp] maps to a
/// distinct source: Pi and on-device EDSDK are both sidecars behind the Flutter capture
/// screen, so they leave the source alone and keep whatever the build already used.
void setConfiguredCameraSource(CameraSource? source) {
  _configuredCameraSource = source;
}

/// The configured camera source: kiosk settings first, then the build-time define.
///
/// Settings win over the define so a booth can be switched from the ZenAI admin without a
/// rebuild; the define stays as the lab override for a device that has no kiosk yet.
CameraSource resolveCameraSource({
  @visibleForTesting String? overrideDefine,
  @visibleForTesting CameraSource? overrideConfigured,
  @visibleForTesting bool ignoreConfigured = false,
}) {
  if (!ignoreConfigured) {
    final configured = overrideConfigured ?? _configuredCameraSource;
    if (configured != null) return configured;
  }
  final raw = overrideDefine ?? kCameraSourceDefine;
  if (raw.trim().isEmpty) return CameraSource.device;
  return cameraSourceFromName(raw);
}

/// True when the booth should hand capture to the native direct-PTP screen.
bool get usesDirectPtpCamera =>
    resolveCameraSource() == CameraSource.directPtp;

/// Prefix for camera ids minted by the direct-PTP capture screen, e.g. `ptp:EOS`.
///
/// Mirrors the `sidecar:` prefix that `isSidecarCameraId` matches. Both mean the
/// same thing downstream — the still came from a tethered DSLR, not from a live
/// preview surface — and code that special-cases one almost always needs both.
const String kDirectPtpCameraIdPrefix = 'ptp:';

/// True when [cameraId] identifies the directly tethered DSLR.
bool isDirectPtpCameraId(String? cameraId) =>
    (cameraId?.trim() ?? '').startsWith(kDirectPtpCameraIdPrefix);
