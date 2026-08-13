import 'package:flutter/foundation.dart' show visibleForTesting;

import '../models/app_settings_model.dart';

/// Canon EDSDK sidecar configuration.
///
/// The sidecar runs locally on the Android box at 127.0.0.1:8791.
/// Defaults are set to localhost so the APK works without any dart-defines.
/// Override at build time if needed:
/// ```
/// --dart-define=CAMERA_SIDECAR_URL=http://127.0.0.1:8791
/// ```
class CameraSidecarConfig {
  const CameraSidecarConfig({
    required this.enabled,
    required this.baseUrl,
    this.livePreviewEnabled = false,
  });

  final bool enabled;
  final String baseUrl;

  /// When true with [isConfigured], pose UI shows the EDSDK sidecar live view.
  final bool livePreviewEnabled;

  bool get isConfigured =>
      enabled && baseUrl.trim().isNotEmpty;

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

/// Sidecar listen port.
const int kCameraSidecarDefaultPort = 8791;

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

/// Returns the environment (dart-define) config.
///
/// Admin settings are intentionally ignored — the sidecar always runs locally
/// on the Android box at 127.0.0.1:8791 and does not use a Pi connection.
CameraSidecarConfig resolveCameraSidecarConfig(
  AppSettingsModel? settings, {
  CameraSidecarConfig? environment,
}) {
  return environment ?? CameraSidecarConfig.fromEnvironment();
}
