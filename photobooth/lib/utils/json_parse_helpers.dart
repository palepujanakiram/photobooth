/// Defensive JSON coercions for API models (avoids `_CastError` on null/mismatch).
abstract final class JsonParseHelpers {
  static String stringValue(dynamic value, {String fallback = ''}) {
    if (value == null) return fallback;
    if (value is String) return value;
    return value.toString();
  }

  static String? stringOrNull(dynamic value) {
    if (value == null) return null;
    if (value is String) return value;
    return value.toString();
  }

  static int? intOrNull(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return null;
  }

  static bool? boolOrNull(dynamic value) {
    if (value is bool) return value;
    return null;
  }

  static DateTime? dateTimeOrNull(dynamic value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return DateTime.tryParse(trimmed);
  }
}
