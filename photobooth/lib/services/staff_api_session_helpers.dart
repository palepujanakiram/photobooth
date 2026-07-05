/// Parses staff-authenticated session API responses for payment thumbnails.
abstract final class StaffApiSessionHelpers {
  static const List<String> _sessionIdKeys = [
    'id',
    'sessionId',
    'session_id',
  ];

  static const List<String> _imageHintKeys = [
    'latestImageUrl',
    'latest_image_url',
    'userImageUrl',
    'user_image_url',
  ];

  static const List<String> _generatedListKeys = [
    'generatedImages',
    'generated_images',
    'images',
  ];

  /// Returns a session map when [data] looks like session JSON for [expectedSessionId].
  ///
  /// Rejects API error objects and SPA/HTML fallbacks (non-map bodies).
  static Map<String, dynamic>? parseSessionResponse(
    dynamic data, {
    required String expectedSessionId,
  }) {
    if (data is! Map) return null;

    final raw = Map<String, dynamic>.from(data);
    final err = raw['error']?.toString().trim();
    if (err != null && err.isNotEmpty) return null;

    final expected = expectedSessionId.trim();
    if (expected.isEmpty) return null;

    final direct = _matchSessionDocument(raw, expected);
    if (direct != null) return direct;

    final nested = raw['session'];
    if (nested is Map) {
      return _matchSessionDocument(Map<String, dynamic>.from(nested), expected);
    }

    return null;
  }

  static Map<String, dynamic>? _matchSessionDocument(
    Map<String, dynamic> doc,
    String expectedId,
  ) {
    final docId = sessionIdFrom(doc);
    if (docId == expectedId) return doc;
    if (docId == null && hasImageHints(doc)) return doc;
    return null;
  }

  static String? sessionIdFrom(Map<String, dynamic> map) {
    for (final key in _sessionIdKeys) {
      final v = map[key];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return null;
  }

  static bool hasImageHints(Map<String, dynamic> map) {
    for (final key in _imageHintKeys) {
      final v = map[key];
      if (v is String && v.trim().isNotEmpty) return true;
    }
    for (final key in _generatedListKeys) {
      final v = map[key];
      if (v is List && v.isNotEmpty) return true;
    }
    return false;
  }
}
