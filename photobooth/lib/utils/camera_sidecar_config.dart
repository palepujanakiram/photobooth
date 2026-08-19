import 'package:flutter/foundation.dart' show visibleForTesting;

import '../models/app_settings_model.dart';
import 'camera_source_config.dart';

/// Where the DSLR sidecar runs for this booth.
///
/// - [CameraConnectionMode.pi]: LAN Pi (`fotozen-sidecar` / gphoto2) via ZenAI host/port
/// - [CameraConnectionMode.direct]: on-device Canon EDSDK at `127.0.0.1:8791`
/// - [CameraConnectionMode.directPtp]: pure-Kotlin PTP over USB, no sidecar at all
enum CameraConnectionMode {
  pi,
  direct,

  /// ZenAI's "Direct PTP (native USB, no EDSDK)".
  ///
  /// The odd one out: [pi] and [direct] both speak HTTP to a sidecar and differ only in
  /// *where* that sidecar runs, so both keep the Flutter capture screen. This one has no
  /// sidecar to talk to — capture lives in `CanonCaptureActivity` — so it is the only mode
  /// that changes which POSE screen the booth opens.
  directPtp;

  /// True when stills come from a tethered DSLR rather than a webcam or capture card.
  bool get isDslr => true;

  /// True when this mode is served by an HTTP sidecar (Pi or on-device EDSDK).
  bool get usesSidecar => this == pi || this == direct;
}

/// Canon / Pi sidecar configuration for Flutter capture + pose preview.
///
/// Mode is chosen by ZenAI `cameraConnectionMode`, else
/// `--dart-define=CAMERA_CONNECTION_MODE=pi|direct`, else inferred from the
/// admin host (loopback → direct, remote → pi).
class CameraSidecarConfig {
  const CameraSidecarConfig({
    required this.enabled,
    required this.baseUrl,
    this.livePreviewEnabled = false,
    this.connectionMode = CameraConnectionMode.direct,
  });

  final bool enabled;
  final String baseUrl;

  /// When true with [isConfigured], pose UI shows sidecar live view.
  final bool livePreviewEnabled;

  /// Pi LAN vs on-device USB EDSDK.
  final CameraConnectionMode connectionMode;

  bool get isConfigured => enabled && baseUrl.trim().isNotEmpty;

  bool get isDirectConnection =>
      connectionMode == CameraConnectionMode.direct;

  bool get isPiConnection => connectionMode == CameraConnectionMode.pi;

  /// Native PTP over USB. No sidecar, so [isConfigured] is always false here.
  bool get isDirectPtpConnection =>
      connectionMode == CameraConnectionMode.directPtp;

  /// Live MJPEG preview is requested and sidecar is configured.
  bool get shouldShowLivePreview => isConfigured && livePreviewEnabled;

  /// `GET /camera/live` URL — kept for API compatibility, unused by sidecar poller.
  String get livePreviewUrl {
    if (!isConfigured) return '';
    final base = Uri.parse(baseUrl.trim());
    final path = _joinPath(base.path, '/camera/live');
    return base.replace(path: path).toString();
  }

  /// `POST /camera/preview?download=1` single-frame URL used by the pose poller.
  String get previewFrameUrl {
    if (!isConfigured) return '';
    final base = Uri.parse(baseUrl.trim());
    final path = _joinPath(base.path, '/camera/preview');
    return base.replace(
      path: path,
      queryParameters: const {'download': '1'},
    ).toString();
  }

  static String _joinPath(String basePath, String path) {
    final left = basePath.endsWith('/')
        ? basePath.substring(0, basePath.length - 1)
        : basePath;
    final right = path.startsWith('/') ? path : '/$path';
    if (left.isEmpty || left == '/') return right;
    return '$left$right';
  }

  static CameraSidecarConfig fromEnvironment() {
    final mode = parseCameraConnectionMode(cameraConnectionModeDefine) ??
        CameraConnectionMode.direct;
    return CameraSidecarConfig(
      enabled: _envFlag(cameraSidecarEnabledDefine),
      baseUrl: cameraSidecarUrlDefine.trim().replaceAll(RegExp(r'/$'), ''),
      livePreviewEnabled: _envFlag(cameraSidecarLivePreviewDefine),
      connectionMode: mode,
    );
  }

  @visibleForTesting
  static bool envFlagForTesting(String raw) => _envFlag(raw);

  static bool _envFlag(String raw) {
    final v = raw.trim().toLowerCase();
    return v == '1' || v == 'true' || v == 'yes' || v == 'on';
  }

  static const String cameraConnectionModeDefine = String.fromEnvironment(
    'CAMERA_CONNECTION_MODE',
    defaultValue: '',
  );

  static const String cameraSidecarEnabledDefine = String.fromEnvironment(
    'CAMERA_SIDECAR_ENABLED',
    defaultValue: 'true',
  );

  static const String cameraSidecarUrlDefine = String.fromEnvironment(
    'CAMERA_SIDECAR_URL',
    defaultValue: 'http://127.0.0.1:8791',
  );

  static const String cameraSidecarLivePreviewDefine = String.fromEnvironment(
    'CAMERA_SIDECAR_LIVE_PREVIEW',
    defaultValue: 'true',
  );
}

/// On-device EDSDK sidecar listen port / default URL.
const int kCameraSidecarDefaultPort = 8791;
const String kDirectCameraSidecarBaseUrl = 'http://127.0.0.1:8791';

/// Parses `pi` / `direct` (case-insensitive). Unknown / empty → null.
CameraConnectionMode? parseCameraConnectionMode(String? raw) {
  switch ((raw ?? '').trim().toLowerCase()) {
    case 'pi':
    case 'raspberry':
    case 'raspberry_pi':
    case 'lan':
      return CameraConnectionMode.pi;
    case 'direct':
    case 'usb':
    case 'edsdk':
    case 'local':
    case 'android':
      return CameraConnectionMode.direct;
    // ZenAI sends `direct_ptp` (see kiosk-edit.tsx). The rest are tolerated for the same
    // reason the other arms have aliases: this value arrives from remote kiosk settings,
    // and a near-miss should not silently drop the booth onto a different camera stack.
    case 'direct_ptp':
    case 'directptp':
    case 'direct-ptp':
    case 'ptp':
    case 'native_ptp':
      return CameraConnectionMode.directPtp;
    default:
      return null;
  }
}

/// Publishes the POSE screen implied by kiosk settings. Call whenever settings change.
///
/// Only `direct_ptp` maps to a distinct capture screen. Pi and on-device EDSDK both drive
/// the Flutter capture screen through an HTTP sidecar and differ only in the sidecar's
/// address, so they clear the override and leave the booth on whatever the build selected —
/// which keeps those two flows behaving exactly as they do on main.
///
/// Applied on every settings load, not once at startup, so an operator switching a kiosk's
/// connection mode in ZenAI takes effect on the next settings fetch rather than needing the
/// booth reinstalled.
void applyCameraSourceFromSettings(AppSettingsModel? settings) {
  final mode = resolveCameraConnectionMode(settings);
  setConfiguredCameraSource(
    mode == CameraConnectionMode.directPtp ? CameraSource.directPtp : null,
  );
}

bool isLoopbackCameraHost(String? host) {
  final h = (host ?? '').trim().toLowerCase();
  return h == '127.0.0.1' ||
      h == 'localhost' ||
      h == '::1' ||
      h == '0.0.0.0';
}

/// Normalizes a URL path prefix (leading slash, no trailing slash on root).
String resolveCameraSidecarPath(String? rawPath) {
  final raw = rawPath?.trim() ?? '';
  if (raw.isEmpty || raw == '/') return '/';
  return raw.startsWith('/') ? raw : '/$raw';
}

/// Builds `http://{host}:{port}` plus optional path prefix (no trailing slash).
String buildCameraSidecarBaseUrl({
  required String host,
  required int port,
  String path = '/',
}) {
  final origin = Uri(scheme: 'http', host: host, port: port).origin;
  final normalized = resolveCameraSidecarPath(path);
  if (normalized == '/') return origin;
  return '$origin${normalized.replaceAll(RegExp(r'/$'), '')}';
}

bool _settingsProvideCameraConfig(AppSettingsModel settings) {
  return settings.cameraEnabled != null ||
      (settings.cameraSidecarHost?.trim().isNotEmpty ?? false) ||
      settings.cameraSidecarPort != null ||
      settings.cameraSidecarPath != null ||
      settings.cameraLivePreviewEnabled != null ||
      (settings.cameraConnectionMode?.trim().isNotEmpty ?? false);
}

/// Resolve mode: admin → dart-define → infer from host → direct default.
CameraConnectionMode resolveCameraConnectionMode(
  AppSettingsModel? settings, {
  CameraSidecarConfig? environment,
}) {
  final fromSettings = parseCameraConnectionMode(settings?.cameraConnectionMode);
  if (fromSettings != null) return fromSettings;

  final env = environment ?? CameraSidecarConfig.fromEnvironment();
  final fromEnv = parseCameraConnectionMode(
    CameraSidecarConfig.cameraConnectionModeDefine,
  );
  if (fromEnv != null) return fromEnv;

  final host = settings?.cameraSidecarHost?.trim() ?? '';
  if (settings?.cameraEnabled == true && host.isNotEmpty) {
    return isLoopbackCameraHost(host)
        ? CameraConnectionMode.direct
        : CameraConnectionMode.pi;
  }

  // Prefer the environment's declared mode (defaults to direct on this branch).
  return env.connectionMode;
}

CameraSidecarConfig _directConfig({
  required CameraSidecarConfig env,
  required AppSettingsModel? settings,
}) {
  // cameraEnabled in ZenAI gates the Pi/LAN sidecar. On-device EDSDK stays
  // available whenever the bundled sidecar is on — a USB DSLR on the Mini PC
  // must still work when GSM left cameraEnabled false.
  final enabled = settings?.cameraEnabled == true || env.enabled;
  // Direct USB has no HDMI card path — always show EDSDK EVF for pose.
  // Admin "Show live preview" is for Pi/HDMI hybrid booths only.
  final live = true;
  final base = env.baseUrl.trim().isNotEmpty
      ? env.baseUrl.trim().replaceAll(RegExp(r'/$'), '')
      : kDirectCameraSidecarBaseUrl;
  return CameraSidecarConfig(
    enabled: enabled,
    baseUrl: base,
    livePreviewEnabled: live,
    connectionMode: CameraConnectionMode.direct,
  );
}

CameraSidecarConfig _piConfig({
  required CameraSidecarConfig env,
  required AppSettingsModel settings,
}) {
  final host = settings.cameraSidecarHost?.trim() ?? '';
  final portRaw = settings.cameraSidecarPort;
  final port = (portRaw != null && portRaw > 0 && portRaw <= 65535)
      ? portRaw
      : kCameraSidecarDefaultPort;
  final enabled = settings.cameraEnabled == true && host.isNotEmpty;
  final baseUrl = host.isEmpty
      ? ''
      : buildCameraSidecarBaseUrl(
          host: host,
          port: port,
          path: resolveCameraSidecarPath(settings.cameraSidecarPath),
        );
  return CameraSidecarConfig(
    enabled: enabled,
    baseUrl: baseUrl,
    livePreviewEnabled: settings.cameraLivePreviewEnabled == true,
    connectionMode: CameraConnectionMode.pi,
  );
}

/// Hybrid resolver: [CameraConnectionMode.pi] uses ZenAI host/port;
/// [CameraConnectionMode.direct] uses the on-device EDSDK localhost sidecar.
CameraSidecarConfig resolveCameraSidecarConfig(
  AppSettingsModel? settings, {
  CameraSidecarConfig? environment,
}) {
  final env = environment ?? CameraSidecarConfig.fromEnvironment();
  final mode = resolveCameraConnectionMode(settings, environment: env);

  if (mode == CameraConnectionMode.directPtp) {
    // No sidecar exists in this mode — capture is native, over USB. Returning a config
    // that is deliberately *not* `isConfigured` is what switches off the entire Flutter
    // sidecar surface in one place: the live-preview poller, the pose warm-up, the
    // capture-screen sidecar branches and the `/health` probe all key off that flag, so
    // none of them start polling `127.0.0.1:8791` for a process that was never launched.
    return const CameraSidecarConfig(
      enabled: false,
      baseUrl: '',
      livePreviewEnabled: false,
      connectionMode: CameraConnectionMode.directPtp,
    );
  }

  if (mode == CameraConnectionMode.direct) {
    return _directConfig(env: env, settings: settings);
  }

  if (settings == null || !_settingsProvideCameraConfig(settings)) {
    // Pi mode requested via dart-define but no admin host yet.
    return CameraSidecarConfig(
      enabled: false,
      baseUrl: '',
      livePreviewEnabled: false,
      connectionMode: CameraConnectionMode.pi,
    );
  }

  return _piConfig(env: env, settings: settings);
}
