import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../utils/camera_sidecar_config.dart';
import '../utils/logger.dart';

/// HTTP client for the booth Pi `fotozen-sidecar` (gphoto2 / FZ200D).
class LocalCameraService {
  LocalCameraService({
    CameraSidecarConfig? config,
    http.Client? client,
    Duration? healthTimeout,
    Duration? captureTimeout,
  })  : _config = config ?? CameraSidecarConfig.fromEnvironment(),
        _client = client ?? http.Client(),
        _healthTimeout = healthTimeout ?? const Duration(seconds: 2),
        _captureTimeout = captureTimeout ?? const Duration(seconds: 60);

  final CameraSidecarConfig _config;
  final http.Client _client;
  final Duration _healthTimeout;
  final Duration _captureTimeout;

  bool get isConfigured => _config.isConfigured;

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

  Map<String, String> get _headers {
    final headers = <String, String>{
      'Accept': 'application/json, image/jpeg, */*',
    };
    if (_config.token.isNotEmpty) {
      headers['X-Camera-Token'] = _config.token;
    }
    return headers;
  }

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

  /// Triggers tethered capture and returns JPEG bytes.
  Future<Uint8List> capture() async {
    if (!isConfigured) {
      throw StateError('Camera sidecar is not configured');
    }
    final response = await _client
        .post(
          _uri('/camera/capture', const {'download': '1'}),
          headers: _headers,
        )
        .timeout(_captureTimeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final preview = response.body.length > 240
          ? response.body.substring(0, 240)
          : response.body;
      throw StateError(
        'Camera sidecar capture failed (${response.statusCode}): $preview',
      );
    }

    final bytes = response.bodyBytes;
    if (bytes.isEmpty) {
      throw StateError('Camera sidecar returned empty capture');
    }
    // Error JSON sometimes returned with wrong content-type.
    if (bytes.length < 512 &&
        bytes.length >= 2 &&
        bytes[0] == 0x7b /* { */) {
      final asText = utf8.decode(bytes, allowMalformed: true);
      throw StateError('Camera sidecar capture error: $asText');
    }
    return Uint8List.fromList(bytes);
  }

  void dispose() {
    _client.close();
  }
}
