import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../utils/camera_sidecar_config.dart';
import '../utils/logger.dart';

/// Long-edge cap requested from Pi on still download (matches kiosk normalize).
const int kSidecarCaptureMaxLongEdge = 1920;

/// JPEG quality for Pi-resized stills.
const int kSidecarCaptureJpegQuality = 85;

/// HTTP client for the booth Pi `fotozen-sidecar` (gphoto2 / FZ200D).
class LocalCameraService {
  LocalCameraService({
    CameraSidecarConfig? config,
    http.Client? client,
    Duration? healthTimeout,
    Duration? captureTimeout,
  })  : _config = config ?? CameraSidecarConfig.fromEnvironment(),
        _client = client ?? http.Client(),
        _healthTimeout = healthTimeout ?? const Duration(seconds: 5),
        _captureTimeout = captureTimeout ?? const Duration(seconds: 60);

  final CameraSidecarConfig _config;
  final http.Client _client;
  final Duration _healthTimeout;
  final Duration _captureTimeout;

  bool get isConfigured => _config.isConfigured;

  /// ZenAI `cameraLivePreviewEnabled` and sidecar host are both set.
  bool get shouldShowLivePreview => _config.shouldShowLivePreview;

  String get livePreviewUrl => _config.livePreviewUrl;

  String get previewFrameUrl => _config.previewFrameUrl;

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = Uri.parse(_config.baseUrl);
    return base.replace(
      path: _joinPath(base.path, path),
      queryParameters: query,
    );
  }

  static String _joinPath(String basePath, String path) {
    final left = basePath.endsWith('/')
        ? basePath.substring(0, basePath.length - 1)
        : basePath;
    final right = path.startsWith('/') ? path : '/$path';
    if (left.isEmpty || left == '/') return right;
    return '$left$right';
  }

  Map<String, String> get _headers => const {
        'Accept': 'application/json, image/jpeg, */*',
      };

  /// True when sidecar reports a connected camera.
  Future<bool> isHealthy() async {
    if (!isConfigured) return false;
    try {
      final response = await _client
          .get(_uri('/health'), headers: _headers)
          .timeout(_healthTimeout);
      if (response.statusCode != 200) return false;
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) return false;
      return body['ok'] == true && body['connected'] == true;
    } catch (e) {
      AppLogger.warning('Camera sidecar health failed: $e');
      return false;
    }
  }

  /// Single gphoto2 live-view JPEG for pose UI polling.
  Future<Uint8List> fetchPreviewJpeg({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (!isConfigured) {
      throw StateError('Camera sidecar is not configured');
    }
    final response = await _client
        .post(
          _uri('/camera/preview', const {'download': '1'}),
          headers: _headers,
        )
        .timeout(timeout);
    return _requireJpegBytes(response, action: 'preview');
  }

  /// Triggers tethered capture and returns a kiosk-sized JPEG from the Pi.
  ///
  /// Requests [maxLongEdge] / [jpegQuality] so the sidecar downscales on-device.
  /// When [resumeLiveView] is true (default), the Pi re-enters Canon Live View
  /// after the still so HDMI capture-card preview recovers without a manual
  /// LV button press (`fotozen-sidecar` ≥ v1.2.1).
  Future<Uint8List> capture({
    int maxLongEdge = kSidecarCaptureMaxLongEdge,
    int jpegQuality = kSidecarCaptureJpegQuality,
    bool resumeLiveView = true,
  }) async {
    if (!isConfigured) {
      throw StateError('Camera sidecar is not configured');
    }
    final response = await _client
        .post(
          _uri('/camera/capture', {
            'download': '1',
            'maxLongEdge': '$maxLongEdge',
            'jpegQuality': '$jpegQuality',
            'resumeLiveView': resumeLiveView ? '1' : '0',
          }),
          headers: _headers,
        )
        .timeout(_captureTimeout);
    return _requireJpegBytes(response, action: 'capture');
  }

  /// Arms Canon Live View over USB so HDMI → capture card is not blank.
  ///
  /// Call before opening UVC pose and again before reopening after a still
  /// (`fotozen-sidecar` ≥ v1.2.3 holds LV with a capture-movie session).
  /// Best-effort — `holding` means the Pi kept the PTP session open.
  Future<({bool enabled, bool woke, bool holding})> ensureLiveView({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (!isConfigured) {
      throw StateError('Camera sidecar is not configured');
    }
    final response = await _client
        .post(_uri('/camera/live-view'), headers: _headers)
        .timeout(timeout);
    final body = _decodeLiveViewBody(response);
    final enabled = body['enabled'] == true;
    final woke = body['woke'] == true;
    final holding = body['holding'] == true;
    // 502 with holding=false is a hard failure; 200 or any enabled/holding ok.
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (!enabled && !holding) {
        final preview = response.body.length > 240
            ? response.body.substring(0, 240)
            : response.body;
        throw StateError(
          'Camera sidecar live-view failed (${response.statusCode}): $preview',
        );
      }
    }
    return (enabled: enabled, woke: woke, holding: holding);
  }

  /// Best-effort booth breadcrumb → Pi `POST /camera/client-log` (never throws).
  Future<void> postClientEvent(
    String type, [
    Map<String, Object?>? detail,
  ]) async {
    if (!isConfigured) return;
    try {
      await _client
          .post(
            _uri('/camera/client-log'),
            headers: {
              ..._headers,
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'type': type,
              if (detail != null) 'detail': detail,
            }),
          )
          .timeout(const Duration(milliseconds: 800));
    } catch (e) {
      AppLogger.debug('Camera sidecar client-log failed: $e');
    }
  }

  Map<String, dynamic> _decodeLiveViewBody(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map<String, dynamic>) return body;
    } catch (_) {
      // fall through
    }
    throw StateError('Camera sidecar live-view returned invalid JSON');
  }

  Uint8List _requireJpegBytes(http.Response response, {required String action}) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final preview = response.body.length > 240
          ? response.body.substring(0, 240)
          : response.body;
      throw StateError(
        'Camera sidecar $action failed (${response.statusCode}): $preview',
      );
    }

    final bytes = response.bodyBytes;
    if (bytes.isEmpty) {
      throw StateError('Camera sidecar returned empty $action');
    }
    // Error JSON sometimes returned with wrong content-type.
    if (bytes.length < 512 &&
        bytes.length >= 2 &&
        bytes[0] == 0x7b /* { */) {
      final asText = utf8.decode(bytes, allowMalformed: true);
      throw StateError('Camera sidecar $action error: $asText');
    }
    return Uint8List.fromList(bytes);
  }

  void dispose() {
    _client.close();
  }
}
