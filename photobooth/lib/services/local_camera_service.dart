import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../utils/camera_sidecar_config.dart';
import '../utils/logger.dart';
import '../utils/sidecar_error_parse.dart';
import 'session_manager.dart';

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
  final Random _random = Random();

  /// Last correlation id used on a sidecar call (also sent as header).
  String? lastCorrId;

  DateTime? _lastHealthyAt;

  /// True when a recent LV/capture succeeded — skip another health RTT.
  bool get recentlyHealthy {
    final at = _lastHealthyAt;
    if (at == null) return false;
    return DateTime.now().difference(at) < const Duration(seconds: 30);
  }

  void markHealthy() {
    _lastHealthyAt = DateTime.now();
  }

  bool get isConfigured => _config.isConfigured;

  bool _forceLivePreview = false;

  /// ZenAI `cameraLivePreviewEnabled`, or POSE forcing USB MJPEG (AI + Classic).
  bool get shouldShowLivePreview =>
      _config.shouldShowLivePreview || _forceLivePreview;

  /// HDMI→UVC is often blank on FZ200D; force Pi USB MJPEG for AI + Classic pose.
  void setForceLivePreview(bool enabled) {
    _forceLivePreview = enabled;
  }

  String get livePreviewUrl => _config.livePreviewUrl;

  String get previewFrameUrl => _config.previewFrameUrl;

  /// Host:port for pose diagnostics (no secrets).
  String get baseUrlLabel {
    try {
      final u = Uri.parse(_config.baseUrl);
      return '${u.host}:${u.hasPort ? u.port : 8791}';
    } catch (_) {
      return _config.baseUrl;
    }
  }

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

  String newCorrId() {
    final id =
        'c${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}'
        '${_random.nextInt(0xffffff).toRadixString(16).padLeft(6, '0')}';
    lastCorrId = id;
    return id;
  }

  Map<String, String> _headers({String? corrId}) {
    final id = corrId ?? lastCorrId ?? newCorrId();
    lastCorrId = id;
    return {
      'Accept': 'application/json, image/jpeg, */*',
      'X-Fotozen-Corr-Id': id,
    };
  }

  /// True when sidecar reports a connected camera.
  Future<bool> isHealthy({String? corrId}) async {
    if (!isConfigured) return false;
    final id = corrId ?? newCorrId();
    final t0 = DateTime.now();
    try {
      final response = await _client
          .get(_uri('/health'), headers: _headers(corrId: id))
          .timeout(_healthTimeout);
      final ms = DateTime.now().difference(t0).inMilliseconds;
      if (response.statusCode != 200) {
        AppLogger.warning(
          'Camera sidecar health status=${response.statusCode} ms=$ms corr=$id',
        );
        return false;
      }
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) return false;
      final ok = body['ok'] == true && body['connected'] == true;
      AppLogger.info(
        'Camera sidecar health ok=$ok connected=${body['connected']} '
        'backend=${body['backend']} ms=$ms corr=$id',
      );
      if (ok) markHealthy();
      return ok;
    } catch (e) {
      final ms = DateTime.now().difference(t0).inMilliseconds;
      final info = parseSidecarError(e);
      AppLogger.warning(
        'Camera sidecar health failed ms=$ms corr=$id '
        'code=${info.code} eds=${info.edsErrorHex}: $e',
      );
      return false;
    }
  }

  /// Single gphoto2 live-view JPEG for pose UI polling.
  Future<Uint8List> fetchPreviewJpeg({
    Duration timeout = const Duration(seconds: 5),
    String? corrId,
  }) async {
    if (!isConfigured) {
      throw StateError('Camera sidecar is not configured');
    }
    final response = await _client
        .post(
          _uri('/camera/preview', const {'download': '1'}),
          headers: _headers(corrId: corrId),
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
    String? corrId,
  }) async {
    if (!isConfigured) {
      throw StateError('Camera sidecar is not configured');
    }
    final id = corrId ?? newCorrId();
    final t0 = DateTime.now();
    AppLogger.info(
      'Camera sidecar capture HTTP begin maxEdge=$maxLongEdge '
      'q=$jpegQuality resumeLV=$resumeLiveView corr=$id',
    );
    unawaited(
      postClientEvent('capture_http_begin', {
        'maxLongEdge': maxLongEdge,
        'jpegQuality': jpegQuality,
        'resumeLiveView': resumeLiveView,
        'corrId': id,
      }),
    );
    final progress = Timer.periodic(const Duration(seconds: 5), (timer) {
      final elapsed = DateTime.now().difference(t0).inMilliseconds;
      AppLogger.warning(
        'Camera sidecar capture still waiting elapsedMs=$elapsed corr=$id',
      );
      unawaited(
        postClientEvent('capture_progress', {
          'elapsedMs': elapsed,
          'corrId': id,
        }),
      );
    });
    try {
      final response = await _client
          .post(
            _uri('/camera/capture', {
              'download': '1',
              'maxLongEdge': '$maxLongEdge',
              'jpegQuality': '$jpegQuality',
              'resumeLiveView': resumeLiveView ? '1' : '0',
            }),
            headers: _headers(corrId: id),
          )
          .timeout(_captureTimeout);
      final ms = DateTime.now().difference(t0).inMilliseconds;
      AppLogger.info(
        'Camera sidecar capture HTTP status=${response.statusCode} '
        'bytes=${response.bodyBytes.length} ms=$ms corr=$id',
      );
      return _requireJpegBytes(response, action: 'capture');
    } on TimeoutException catch (e) {
      final ms = DateTime.now().difference(t0).inMilliseconds;
      AppLogger.warning(
        'Camera sidecar capture timeout ms=$ms corr=$id: $e',
      );
      unawaited(
        postClientEvent('capture_timeout', {
          'timeoutMs': _captureTimeout.inMilliseconds,
          'elapsedMs': ms,
          'corrId': id,
        }),
      );
      rethrow;
    } finally {
      progress.cancel();
    }
  }

  /// Exit movie LV during the countdown so [capture] can shutter at timer zero.
  ///
  /// Requires fotozen-sidecar ≥ 1.2.19 (`POST /camera/prepare-still`).
  Future<void> prepareStill({
    Duration timeout = const Duration(seconds: 20),
    String? corrId,
  }) async {
    if (!isConfigured) {
      throw StateError('Camera sidecar is not configured');
    }
    final id = corrId ?? newCorrId();
    final t0 = DateTime.now();
    AppLogger.info('Camera sidecar prepare-still begin corr=$id');
    final response = await _client
        .post(_uri('/camera/prepare-still'), headers: _headers(corrId: id))
        .timeout(timeout);
    final ms = DateTime.now().difference(t0).inMilliseconds;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      AppLogger.warning(
        'Camera sidecar prepare-still failed status=${response.statusCode} '
        'ms=$ms corr=$id body=${response.body}',
      );
      throw StateError(
        'Camera sidecar prepare-still failed '
        '(${response.statusCode}): ${response.body}',
      );
    }
    AppLogger.info('Camera sidecar prepare-still ok ms=$ms corr=$id');
  }

  /// Arms Canon Live View over USB so HDMI → capture card is not blank.
  ///
  /// Call before opening UVC pose and again before reopening after a still
  /// (`fotozen-sidecar` ≥ v1.2.3 holds LV with a capture-movie session).
  /// Best-effort — `holding` means the Pi kept the PTP session open.
  Future<({bool enabled, bool woke, bool holding})> ensureLiveView({
    Duration timeout = const Duration(seconds: 12),
    String? corrId,
  }) async {
    if (!isConfigured) {
      throw StateError('Camera sidecar is not configured');
    }
    final id = corrId ?? newCorrId();
    final t0 = DateTime.now();
    AppLogger.info('Camera sidecar live-view begin corr=$id');
    final response = await _client
        .post(_uri('/camera/live-view'), headers: _headers(corrId: id))
        .timeout(timeout);
    final ms = DateTime.now().difference(t0).inMilliseconds;
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
        AppLogger.warning(
          'Camera sidecar live-view failed status=${response.statusCode} '
          'ms=$ms corr=$id body=$preview',
        );
        throw StateError(
          'Camera sidecar live-view failed (${response.statusCode}): $preview',
        );
      }
    }
    AppLogger.info(
      'Camera sidecar live-view ok enabled=$enabled woke=$woke '
      'holding=$holding ms=$ms corr=$id',
    );
    if (enabled || holding) markHealthy();
    return (enabled: enabled, woke: woke, holding: holding);
  }

  /// Best-effort booth breadcrumb → Pi `POST /camera/client-log` (never throws).
  Future<void> postClientEvent(
    String type, [
    Map<String, Object?>? detail,
  ]) async {
    if (!isConfigured) return;
    final id = lastCorrId ?? newCorrId();
    final sessionId = SessionManager().sessionId;
    try {
      await _client
          .post(
            _uri('/camera/client-log'),
            headers: {
              ..._headers(corrId: id),
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'type': type,
              'detail': {
                ...?detail,
                'corrId': detail?['corrId'] ?? id,
                if (sessionId != null && sessionId.isNotEmpty)
                  'sessionId': detail?['sessionId'] ?? sessionId,
              },
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
