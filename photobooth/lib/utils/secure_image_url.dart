import '../services/session_manager.dart';
import 'app_config.dart';
import 'secure_image_url_helpers.dart';

/// Helpers for accessing protected image endpoints.
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

  static String absolutize(String url) => _absolutizeIfRelative(url);

  static String withSessionId(String url, {String? sessionId}) {
    final sid = (sessionId ?? SessionManager().sessionId)?.trim();
    if (sid == null || sid.isEmpty) return url;

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

  static String? previewUrlFromStepMap(Map<String, dynamic> data) {
    const topKeys = [
      'previewImageUrl',
      'thumbnailUrl',
      'previewUrl',
      'imageUrl',
    ];
    final top = firstNonEmptyUrlFromMap(data, topKeys, absolutize: absolutize);
    if (top != null) return top;

    final od = data['outputData'];
    if (od is Map) {
      final nested = firstNonEmptyUrlFromMap(
        Map<String, dynamic>.from(od),
        [...topKeys, 'url'],
        absolutize: absolutize,
      );
      if (nested != null) return nested;
    }

    final id = data['inputData'];
    if (id is Map) {
      return firstNonEmptyUrlFromMap(
        Map<String, dynamic>.from(id),
        [...topKeys, 'url'],
        absolutize: absolutize,
      );
    }
    return null;
  }
}
