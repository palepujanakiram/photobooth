import 'package:flutter/foundation.dart' show kIsWeb;

import '../services/session_manager.dart';
import 'app_config.dart';

/// Known API hosts that may appear in absolute URLs returned by the backend.
const _knownApiHosts = {'fotozenai.fly.dev', 'fotozenai-test.fly.dev'};

/// Helpers for accessing protected image endpoints.
///
/// Backend may protect `/api/img/...` resources (403 unless caller sends
/// `X-Kiosk-Session-Token`, has an admin cookie, `?sessionId=...`, or `?shareToken=...`).
/// The kiosk app uses `X-Kiosk-Session-Token` (via ProtectedImageLoader) and `sessionId`.
class SecureImageUrl {
  static bool _isProtectedImgPath(String path) {
    return path.startsWith('/api/img/') || path.startsWith('api/img/');
  }

  static String _baseUrlNoTrailingSlash() {
    const b = AppConfig.baseUrl;
    return b.endsWith('/') ? b.substring(0, b.length - 1) : b;
  }

  /// On web, rewrite absolute API URLs to [AppConfig.baseUrl] (same-origin proxy).
  static String rewriteKnownApiHost(String url) {
    if (!kIsWeb) return url;
    final trimmed = url.trim();
    if (trimmed.isEmpty) return url;
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme) return url;
    if (!_knownApiHosts.contains(uri.host.toLowerCase())) return url;
    final base = Uri.parse(_baseUrlNoTrailingSlash());
    return uri
        .replace(
          scheme: base.scheme,
          host: base.host,
          port: base.hasPort ? base.port : null,
        )
        .toString();
  }

  static String _absolutizeIfRelative(String url) {
    final trimmed = url.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return rewriteKnownApiHost(trimmed);
    }
    final base = _baseUrlNoTrailingSlash();
    if (trimmed.startsWith('/')) return '$base$trimmed';
    return '$base/$trimmed';
  }

  /// Resolves relative API paths to an absolute URL (no `sessionId` appended).
  static String absolutize(String url) => _absolutizeIfRelative(url);

  /// Returns [url] with `sessionId` and `kioskToken` when needed for `/api/img/...`.
  static String withSessionId(String url, {String? sessionId, String? kioskToken}) {
    final sid = (sessionId ?? SessionManager().sessionId)?.trim();
    final token = (kioskToken ?? SessionManager().kioskAuthToken)?.trim();
    if ((sid == null || sid.isEmpty) && (token == null || token.isEmpty)) {
      return url;
    }

    // If it's a protected image path and relative, make it absolute first.
    final maybeAbsolute = _isProtectedImgPath(url.trimLeft())
        ? _absolutizeIfRelative(url)
        : url;

    final Uri uri;
    try {
      uri = Uri.parse(maybeAbsolute);
    } catch (_) {
      return url;
    }

    if (!_isProtectedImgPath(uri.path)) return maybeAbsolute;

    final qp = Map<String, String>.from(uri.queryParameters);
    if (qp.containsKey('shareToken')) {
      return uri.toString();
    }
    if (sid != null && sid.isNotEmpty && !qp.containsKey('sessionId')) {
      qp['sessionId'] = sid;
    }
    if (token != null && token.isNotEmpty && !qp.containsKey('kioskToken')) {
      qp['kioskToken'] = token;
    }
    return uri.replace(queryParameters: qp).toString();
  }

  /// Best-effort preview URL for a `transformation_steps` row from
  /// `GET /api/generation-runs/:runId` (CDN JPEG or legacy nested fields).
  static String? previewUrlFromStepMap(Map<String, dynamic> data) {
    for (final key in [
      'previewImageUrl',
      'thumbnailUrl',
      'previewUrl',
      'imageUrl',
    ]) {
      final v = data[key];
      if (v is String && v.trim().isNotEmpty) {
        return absolutize(v.trim());
      }
    }
    final od = data['outputData'];
    if (od is Map) {
      final m = Map<String, dynamic>.from(od);
      for (final key in [
        'previewImageUrl',
        'thumbnailUrl',
        'previewUrl',
        'imageUrl',
        'url',
      ]) {
        final v = m[key];
        if (v is String && v.trim().isNotEmpty) {
          return absolutize(v.trim());
        }
      }
    }
    final id = data['inputData'];
    if (id is Map) {
      final m = Map<String, dynamic>.from(id);
      for (final key in [
        'previewImageUrl',
        'thumbnailUrl',
        'previewUrl',
        'imageUrl',
        'url',
      ]) {
        final v = m[key];
        if (v is String && v.trim().isNotEmpty) {
          return absolutize(v.trim());
        }
      }
    }
    return null;
  }
}

