import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb, visibleForTesting;

import '../models/app_settings_model.dart';

/// Where the DSLR sidecar / native PTP stack runs for this booth.
///
/// - [CameraConnectionMode.pi]: LAN Pi (`fotozen-sidecar` / gphoto2) via ZenAI host/port
/// - [CameraConnectionMode.direct]: on-device Canon EDSDK at `127.0.0.1:8791`
/// - [CameraConnectionMode.directPtp]: on-device Kotlin PTP + native capture Activity
enum CameraConnectionMode {
  pi,
  direct,
  directPtp,
}

/// Canon / Pi sidecar configuration for Flutter capture + pose preview.
///
/// Mode is chosen by ZenAI `cameraConnectionMode`, else
/// `--dart-define=CAMERA_CONNECTION_MODE=pi|direct|direct_ptp`, else inferred
/// from the admin host (loopback → direct, remote → pi).
class CameraSidecarConfig {
  const CameraSidecarConfig({
    required this.enabled,
    required this.baseUrl,
    this.livePreviewEnabled = false,
    this.connectionMode = CameraConnectionMode.direct,
    this.modeExplicit = false,
  });

  final bool enabled;
  final String baseUrl;

  /// When true with [isConfigured], pose UI shows sidecar live view.
  final bool livePreviewEnabled;

  /// Pi LAN vs on-device USB EDSDK vs native PTP.
  final CameraConnectionMode connectionMode;

  /// True when ZenAI `cameraConnectionMode` or dart-define chose the mode.
  ///
  /// False when the mode was inferred from a leftover sidecar host — Pose may
  /// fall back to on-device USB if that Pi is unreachable.
  final bool modeExplicit;

  bool get isConfigured => enabled && baseUrl.trim().isNotEmpty;

  /// On-device EDSDK USB — only when the sidecar is actually configured.
  /// A disabled/empty config (Flutter web) must not look like a live USB booth.
  bool get isDirectConnection =>
      connectionMode == CameraConnectionMode.direct && isConfigured;

  bool get isPiConnection => connectionMode == CameraConnectionMode.pi;

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
    return fromConnectionModeDefine(
      cameraConnectionModeDefine,
      enabled: _envFlag(cameraSidecarEnabledDefine),
      baseUrl: cameraSidecarUrlDefine.trim().replaceAll(RegExp(r'/$'), ''),
      livePreviewEnabled: _envFlag(cameraSidecarLivePreviewDefine),
    );
  }

  /// Builds config from a parsed `CAMERA_CONNECTION_MODE` value.
  ///
  /// [CameraConnectionMode.directPtp] disables the HTTP sidecar so native PTP
  /// owns USB. Used by [fromEnvironment] and tests (dart-defines are const).
  @visibleForTesting
  static CameraSidecarConfig fromConnectionModeDefine(
    String raw, {
    required bool enabled,
    required String baseUrl,
    required bool livePreviewEnabled,
  }) {
    final fromDefine = parseCameraConnectionMode(raw);
    if (fromDefine == CameraConnectionMode.directPtp) {
      return const CameraSidecarConfig(
        enabled: false,
        baseUrl: '',
        livePreviewEnabled: false,
        connectionMode: CameraConnectionMode.directPtp,
        modeExplicit: true,
      );
    }
    return CameraSidecarConfig(
      enabled: enabled,
      baseUrl: baseUrl,
      livePreviewEnabled: livePreviewEnabled,
      connectionMode: fromDefine ?? CameraConnectionMode.direct,
      modeExplicit: fromDefine != null,
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

/// Parses `pi` / `direct` / `direct_ptp` (case-insensitive). Unknown / empty → null.
CameraConnectionMode? parseCameraConnectionMode(String? raw) {
  switch ((raw ?? '').trim().toLowerCase().replaceAll('-', '_')) {
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
    case 'direct_ptp':
    case 'directptp':
    case 'ptp':
    case 'native_ptp':
      return CameraConnectionMode.directPtp;
    default:
      return null;
  }
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

bool get _runningOnIos {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.iOS;
}

CameraSidecarConfig _disabledSidecarConfig({
  required CameraConnectionMode connectionMode,
  required bool modeExplicit,
}) {
  return CameraSidecarConfig(
    enabled: false,
    baseUrl: '',
    livePreviewEnabled: false,
    connectionMode: connectionMode,
    modeExplicit: modeExplicit,
  );
}

bool _settingsProvideCameraConfig(AppSettingsModel settings) {
  return settings.cameraEnabled != null ||
      (settings.cameraSidecarHost?.trim().isNotEmpty ?? false) ||
      settings.cameraSidecarPort != null ||
      settings.cameraSidecarPath != null ||
      settings.cameraLivePreviewEnabled != null ||
      (settings.cameraConnectionMode?.trim().isNotEmpty ?? false);
}

/// True when ZenAI or dart-define set the mode (do not USB-fallback an
/// explicit Pi booth).
bool cameraConnectionModeIsExplicit(AppSettingsModel? settings) {
  if (parseCameraConnectionMode(settings?.cameraConnectionMode) != null) {
    return true;
  }
  return parseCameraConnectionMode(
        CameraSidecarConfig.cameraConnectionModeDefine,
      ) !=
      null;
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
  required bool modeExplicit,
}) {
  // cameraEnabled in ZenAI gates the Pi/LAN sidecar. On-device EDSDK stays
  // available whenever the bundled sidecar is on — a USB DSLR on the Mini PC
  // must still work when GSM left cameraEnabled false.
  final enabled = settings?.cameraEnabled == true || env.enabled;
  // Direct USB has no HDMI card path — always show EDSDK EVF for pose.
  // Admin "Show live preview" is for Pi/HDMI hybrid booths only.
  const live = true;
  final base = env.baseUrl.trim().isNotEmpty
      ? env.baseUrl.trim().replaceAll(RegExp(r'/$'), '')
      : kDirectCameraSidecarBaseUrl;
  return CameraSidecarConfig(
    enabled: enabled,
    baseUrl: base,
    livePreviewEnabled: live,
    connectionMode: CameraConnectionMode.direct,
    modeExplicit: modeExplicit,
  );
}

CameraSidecarConfig _piConfig({
  required AppSettingsModel settings,
  required bool modeExplicit,
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
    modeExplicit: modeExplicit,
  );
}

/// Hybrid resolver: [CameraConnectionMode.pi] uses ZenAI host/port;
/// [CameraConnectionMode.direct] uses the on-device EDSDK localhost sidecar;
/// [CameraConnectionMode.directPtp] disables the HTTP sidecar (native PTP owns USB).
///
/// Flutter web cannot reach the Mini PC sidecar or USB DSLR, so the browser
/// always falls through to `getUserMedia` instead of waiting on localhost:8791.
///
/// iPhone / iPad have no bundled EDSDK sidecar either — localhost `:8791`
/// would skip CameraX/AVFoundation and show "DSLR live preview unavailable."
/// A ZenAI **Pi** host on the LAN is still allowed on iOS.
CameraSidecarConfig resolveCameraSidecarConfig(
  AppSettingsModel? settings, {
  CameraSidecarConfig? environment,
  @visibleForTesting bool? isWeb,
  @visibleForTesting bool? isIos,
}) {
  if (isWeb ?? kIsWeb) {
    return _disabledSidecarConfig(
      connectionMode: CameraConnectionMode.pi,
      modeExplicit: true,
    );
  }
  final env = environment ?? CameraSidecarConfig.fromEnvironment();
  final mode = resolveCameraConnectionMode(settings, environment: env);
  final modeExplicit = cameraConnectionModeIsExplicit(settings);

  if (mode == CameraConnectionMode.directPtp) {
    return _disabledSidecarConfig(
      connectionMode: CameraConnectionMode.directPtp,
      modeExplicit: modeExplicit,
    );
  }

  if (mode == CameraConnectionMode.direct) {
    if (isIos ?? _runningOnIos) {
      return _disabledSidecarConfig(
        connectionMode: CameraConnectionMode.direct,
        modeExplicit: modeExplicit,
      );
    }
    return _directConfig(
      env: env,
      settings: settings,
      modeExplicit: modeExplicit,
    );
  }

  if (settings == null || !_settingsProvideCameraConfig(settings)) {
    // Pi mode requested via dart-define but no admin host yet.
    return CameraSidecarConfig(
      enabled: false,
      baseUrl: '',
      livePreviewEnabled: false,
      connectionMode: CameraConnectionMode.pi,
      modeExplicit: modeExplicit,
    );
  }

  return _piConfig(
    settings: settings,
    modeExplicit: modeExplicit,
  );
}
