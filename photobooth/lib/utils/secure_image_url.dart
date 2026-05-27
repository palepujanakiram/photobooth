import '../services/session_manager.dart';
import 'app_config.dart';

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

  static String _absolutizeIfRelative(String url) {
    final trimmed = url.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    final base = _baseUrlNoTrailingSlash();
    if (trimmed.startsWith('/')) return '$base$trimmed';
    return '$base/$trimmed';
  }

  /// Resolves relative API paths to an absolute URL (no `sessionId` appended).
  static String absolutize(String url) => _absolutizeIfRelative(url);

  /// Returns [url] with `sessionId=<currentSessionId>` appended when it points to `/api/img/...`
  /// and no other access token is already present.
  static String withSessionId(String url, {String? sessionId}) {
    final sid = (sessionId ?? SessionManager().sessionId)?.trim();
    if (sid == null || sid.isEmpty) return url;

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
    if (qp.containsKey('sessionId') || qp.containsKey('shareToken')) {
      return uri.toString();
    }
    qp['sessionId'] = sid;
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

