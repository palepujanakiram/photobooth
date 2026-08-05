import 'package:flutter/foundation.dart' show visibleForTesting;

import '../models/app_settings_model.dart';

/// LAN FotoZen camera sidecar (Pi gphoto2) configuration.
///
/// Runtime config comes from ZenAI `/api/settings` (kiosk camera fields) via
/// [resolveCameraSidecarConfig]. Lab builds can still force values with:
/// ```
/// --dart-define=CAMERA_SIDECAR_ENABLED=true
/// --dart-define=CAMERA_SIDECAR_URL=http://192.168.2.50:8791
/// ```
class CameraSidecarConfig {
  const CameraSidecarConfig({
    required this.enabled,
    required this.baseUrl,
    this.livePreviewEnabled = false,
  });

  final bool enabled;
  final String baseUrl;

  /// When true with [isConfigured], pose UI should show Pi `/camera/live`
  /// instead of webcam / HDMI capture card.
  final bool livePreviewEnabled;

  bool get isConfigured =>
      enabled && baseUrl.trim().isNotEmpty;

  /// Live MJPEG preview is requested and sidecar is configured.
  bool get shouldShowLivePreview => isConfigured && livePreviewEnabled;

  /// `GET /camera/live` multipart MJPEG URL (Pi gphoto2 live view).
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
    return CameraSidecarConfig(
      enabled: _envFlag(cameraSidecarEnabledDefine),
      baseUrl: cameraSidecarUrlDefine.trim().replaceAll(RegExp(r'/$'), ''),
      livePreviewEnabled: _envFlag(cameraSidecarLivePreviewDefine),
    );
  }

  @visibleForTesting
  static bool envFlagForTesting(String raw) => _envFlag(raw);

  static bool _envFlag(String raw) {
    final v = raw.trim().toLowerCase();
    return v == '1' || v == 'true' || v == 'yes' || v == 'on';
  }

  static const String cameraSidecarEnabledDefine = String.fromEnvironment(
    'CAMERA_SIDECAR_ENABLED',
    defaultValue: '',
  );

  static const String cameraSidecarUrlDefine = String.fromEnvironment(
    'CAMERA_SIDECAR_URL',
    defaultValue: 'http://192.168.2.50:8791',
  );

  static const String cameraSidecarLivePreviewDefine = String.fromEnvironment(
    'CAMERA_SIDECAR_LIVE_PREVIEW',
    defaultValue: '',
  );
}

/// Sidecar default listen port (fotozen-sidecar). ZenAI admin may default to
/// 8080 — operators must set the port that matches the Pi process.
const int kCameraSidecarDefaultPort = 8791;

/// Normalizes admin `cameraSidecarPath` for use as a URL path prefix.
String resolveCameraSidecarPath(String? rawPath) {
  final raw = rawPath?.trim() ?? '';
  if (raw.isEmpty || raw == '/') {
    return '/';
  }
  return raw.startsWith('/') ? raw : '/$raw';
}

/// Builds `http://{host}:{port}` plus optional path prefix (no trailing slash).
String buildCameraSidecarBaseUrl({
  required String host,
  required int port,
  String path = '/',
}) {
  final origin = Uri(
    scheme: 'http',
    host: host,
    port: port,
  ).origin;
  final normalized = resolveCameraSidecarPath(path);
  if (normalized == '/') {
    return origin;
  }
  return '$origin${normalized.replaceAll(RegExp(r'/$'), '')}';
}

bool _settingsProvideCameraConfig(AppSettingsModel settings) {
  return settings.cameraEnabled != null ||
      (settings.cameraSidecarHost?.trim().isNotEmpty ?? false) ||
      settings.cameraSidecarPort != null ||
      settings.cameraSidecarPath != null ||
      settings.cameraLivePreviewEnabled != null;
}

/// Hybrid resolver: ZenAI kiosk settings win when present; otherwise dart-define.
CameraSidecarConfig resolveCameraSidecarConfig(
  AppSettingsModel? settings, {
  CameraSidecarConfig? environment,
}) {
  final env = environment ?? CameraSidecarConfig.fromEnvironment();
  if (settings == null || !_settingsProvideCameraConfig(settings)) {
    return env;
  }

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
  );
}
