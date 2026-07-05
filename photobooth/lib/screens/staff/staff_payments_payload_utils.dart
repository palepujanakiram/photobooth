import '../../utils/app_strings.dart';
import '../../utils/constants.dart';
import '../../utils/secure_image_url.dart';

/// JSON / URL helpers for staff payment list payloads (extracted for Sonar S3776).
abstract final class StaffPaymentsPayloadUtils {
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
    if (trimmed.startsWith(AppStrings.dataImagePrefix)) return trimmed;
    return SecureImageUrl.absolutize(trimmed);
  }

  static const List<String> paymentThumbUrlKeys = [
    'latestImageUrl',
    'latest_image_url',
    'thumbnailUrl',
    'thumbUrl',
    'imageUrl',
    'image_url',
    'generatedImageUrl',
    'generated_image_url',
    'photoUrl',
    'photo_url',
    'sessionImageUrl',
    'previewUrl',
  ];

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
      'latestImageUrl',
      'latest_image_url',
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

  /// First generated-image URL from a session payload (maps or string entries).
  static String? imageUrlFromGeneratedEntry(dynamic first, {String? sessionId}) {
    if (first is Map) {
      final m = Map<String, dynamic>.from(first);
      final u = pickString(m, const [
        'imageUrl',
        'image_url',
        'url',
        'photoUrl',
        'photo_url',
      ]);
      if (u.isNotEmpty) {
        return normalizeImageUrl(u, sessionId: sessionId);
      }
    }
    if (first is String) {
      final u = first.trim();
      if (u.isNotEmpty) {
        return normalizeImageUrl(u, sessionId: sessionId);
      }
    }
    return null;
  }

  /// Resolves a print/preview image URL from [raw] session JSON.
  static String? resolveSessionImageUrl(
    Map<String, dynamic> raw, {
    required String sessionId,
  }) {
    for (final key in const [
      'latestImageUrl',
      'latest_image_url',
      'outputImageUrl',
      'output_image_url',
      'userImagePreviewUrl',
      'user_image_preview_url',
    ]) {
      final direct = pickString(raw, [key]);
      if (direct.isNotEmpty) {
        return normalizeImageUrl(direct, sessionId: sessionId);
      }
    }

    final generated =
        raw['generatedImages'] ?? raw['generated_images'] ?? raw['images'];
    if (generated is List && generated.isNotEmpty) {
      for (var i = generated.length - 1; i >= 0; i--) {
        final fromEntry = imageUrlFromGeneratedEntry(
          generated[i],
          sessionId: sessionId,
        );
        if (fromEntry != null) return fromEntry;
      }
    }
    final any = deepFindFirstUrl(raw);
    if (any != null) {
      return normalizeImageUrl(any, sessionId: sessionId);
    }
    return null;
  }

  /// Last output image from `GET /api/sessions/:id/runs` (staff auth).
  static String? resolveImageUrlFromRunsPayload(
    Map<String, dynamic> raw, {
    required String sessionId,
  }) {
    final runs = raw['runs'];
    if (runs is! List || runs.isEmpty) return null;

    for (var i = runs.length - 1; i >= 0; i--) {
      final run = runs[i];
      if (run is! Map) continue;
      final m = Map<String, dynamic>.from(run);
      final output = pickString(m, const [
        'outputImageUrl',
        'output_image_url',
        'imageUrl',
        'image_url',
      ]);
      if (output.isNotEmpty) {
        return normalizeImageUrl(output, sessionId: sessionId);
      }
    }
    return null;
  }

  /// Bare base64 user image field from session payload (no data-URL prefix).
  static String userImageFieldFromSession(Map<String, dynamic> raw) {
    return pickString(raw, const ['userImageUrl', 'user_image_url']);
  }

  /// Thumbnail URL from a staff payment row (flat fields, then nested session).
  static String? resolvePaymentThumbUrl(
    Map<String, dynamic> payment, {
    required String sessionId,
  }) {
    final sid = sessionId.trim();
    final direct = pickString(payment, paymentThumbUrlKeys);
    if (direct.isNotEmpty) {
      return normalizeImageUrl(direct, sessionId: sid.isEmpty ? null : sid);
    }

    final sessionObj = payment['session'];
    if (sessionObj is Map) {
      final fromSession = resolveSessionImageUrl(
        Map<String, dynamic>.from(sessionObj),
        sessionId: sid,
      );
      if (fromSession != null) return fromSession;
    }

    return null;
  }
}
