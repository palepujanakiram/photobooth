import '../../utils/app_strings.dart';
import '../../utils/constants.dart';
import '../../utils/secure_image_url.dart';

/// JSON / URL helpers for staff payment list payloads (extracted for Sonar S3776).
class StaffPaymentsPayloadUtils {
  StaffPaymentsPayloadUtils._();

  static String baseUrlNoTrailingSlash() {
    const b = AppConstants.kBaseUrl;
    return b.endsWith('/') ? b.substring(0, b.length - 1) : b;
  }

  static String? deepFindFirstValueForKeys(
    dynamic node,
    List<String> keys, {
    int depth = 0,
  }) {
    if (node == null || depth > 5) return null;
    if (node is Map) {
      return _deepFindInMap(node, keys, depth);
    }
    if (node is List) {
      for (final e in node) {
        final found = deepFindFirstValueForKeys(e, keys, depth: depth + 1);
        if (found != null) return found;
      }
    }
    return null;
  }

  static String? _deepFindInMap(
    Map<dynamic, dynamic> node,
    List<String> keys,
    int depth,
  ) {
    final m = Map<String, dynamic>.from(node);
    for (final k in keys) {
      final v = m[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
      if ((k == 'session' || k.toLowerCase() == 'session') && v is Map) {
        final id = Map<String, dynamic>.from(v)['id'];
        if (id is String && id.trim().isNotEmpty) return id.trim();
      }
    }
    for (final v in m.values) {
      final found = deepFindFirstValueForKeys(v, keys, depth: depth + 1);
      if (found != null) return found;
    }
    return null;
  }

  static bool looksLikeUrl(String s) {
    final t = s.trim();
    if (t.isEmpty) return false;
    if (t.startsWith('http://') || t.startsWith('https://')) return true;
    if (t.startsWith('/')) return true;
    if (t.startsWith('api/')) return true;
    if (t.startsWith('api/img/')) return true;
    if (t.startsWith('/api/')) return true;
    return false;
  }

  static String absolutizeIfRelative(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    if (trimmed.startsWith(AppStrings.dataImagePrefix)) return trimmed;
    final base = baseUrlNoTrailingSlash();
    if (trimmed.startsWith('/')) return '$base$trimmed';
    return '$base/$trimmed';
  }

  static String normalizeImageUrl(String raw, {String? sessionId}) {
    final t = raw.trim();
    if (t.isEmpty) return '';
    if (t.startsWith(AppStrings.dataImagePrefix)) return t;
    final absolute = absolutizeIfRelative(t);
    return SecureImageUrl.withSessionId(absolute, sessionId: sessionId);
  }

  static String? deepFindFirstUrl(dynamic node, {int depth = 0}) {
    if (node == null || depth > 4) return null;
    if (node is String) {
      final t = node.trim();
      return looksLikeUrl(t) ? t : null;
    }
    if (node is Map) {
      return _deepFindUrlInMap(node, depth);
    }
    if (node is List) {
      for (final e in node) {
        final found = deepFindFirstUrl(e, depth: depth + 1);
        if (found != null) return found;
      }
    }
    return null;
  }

  static String? _deepFindUrlInMap(Map<dynamic, dynamic> node, int depth) {
    final m = Map<String, dynamic>.from(node);
    for (final k in const [
      'imageUrl',
      'image_url',
      'url',
      'photoUrl',
      'photo_url',
      'thumbnailUrl',
      'thumbUrl',
      'previewUrl',
    ]) {
      final v = m[k];
      if (v is String && looksLikeUrl(v)) return v;
    }
    for (final v in m.values) {
      final found = deepFindFirstUrl(v, depth: depth + 1);
      if (found != null) return found;
    }
    return null;
  }

  static String pickString(Map<String, dynamic> map, List<String> keys) {
    for (final k in keys) {
      final v = map[k];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return '';
  }
}
