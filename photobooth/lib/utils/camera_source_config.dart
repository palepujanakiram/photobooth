import 'package:flutter/foundation.dart' show visibleForTesting;

import '../models/app_settings_model.dart';
import 'camera_sidecar_config.dart';

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
/// Empty by default. Prefer ZenAI `cameraConnectionMode=direct_ptp` for kiosks;
/// this define stays as the lab override.
const String kCameraSourceDefine =
    String.fromEnvironment('CAMERA_SOURCE', defaultValue: '');

/// The configured camera source for this build (dart-define only).
CameraSource resolveCameraSource({
  @visibleForTesting String? overrideDefine,
}) {
  final raw = overrideDefine ?? kCameraSourceDefine;
  if (raw.trim().isEmpty) return CameraSource.device;
  return cameraSourceFromName(raw);
}

/// True when the booth should hand capture to the native direct-PTP screen.
///
/// Order: explicit ZenAI / dart-define [CameraConnectionMode.directPtp], else
/// `CAMERA_SOURCE=direct_ptp`. Explicit `pi` / `direct` never opens PTP.
bool usesDirectPtpCamera({
  AppSettingsModel? settings,
  @visibleForTesting String? overrideSourceDefine,
  @visibleForTesting String? overrideConnectionModeDefine,
}) {
  final fromSettings = parseCameraConnectionMode(settings?.cameraConnectionMode);
  if (fromSettings == CameraConnectionMode.directPtp) return true;
  if (fromSettings == CameraConnectionMode.pi ||
      fromSettings == CameraConnectionMode.direct) {
    return false;
  }

  final fromConnectionDefine = parseCameraConnectionMode(
    overrideConnectionModeDefine ??
        CameraSidecarConfig.cameraConnectionModeDefine,
  );
  if (fromConnectionDefine == CameraConnectionMode.directPtp) return true;
  if (fromConnectionDefine == CameraConnectionMode.pi ||
      fromConnectionDefine == CameraConnectionMode.direct) {
    return false;
  }

  return resolveCameraSource(overrideDefine: overrideSourceDefine) ==
      CameraSource.directPtp;
}
