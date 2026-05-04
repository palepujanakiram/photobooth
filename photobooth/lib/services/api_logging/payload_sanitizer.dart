import 'dart:convert';

/// Sanitizes request/response payloads so logs don't leak secrets or explode in size.
class PayloadSanitizer {
  const PayloadSanitizer({
    this.maxLoggedStringLength = 2000,
  });

  final int maxLoggedStringLength;

  /// Masks authorization tokens for security.
  String maskAuthorization(String auth) {
    if (auth.length <= 20) return '***';
    return '${auth.substring(0, 10)}...${auth.substring(auth.length - 4)}';
  }

  dynamic sanitizeData(dynamic data) {
    if (data == null) return null;
    if (data is Map) {
      return data.map((key, value) => MapEntry(key, sanitizeData(value)));
    }
    if (data is List) {
      return data.map(sanitizeData).toList();
    }
    if (data is String) {
      return sanitizeString(data);
    }
    return data;
  }

  /// Redacts or truncates large strings (especially base64 images).
  String sanitizeString(String value) {
    final lower = value.toLowerCase();
    if (lower.startsWith('data:image') && value.contains('base64,')) {
      return '<base64 image omitted (${value.length} chars)>';
    }
    if (value.length > maxLoggedStringLength) {
      return '${value.substring(0, maxLoggedStringLength)}... '
          '[truncated, ${value.length} chars]';
    }
    return value;
  }

  /// Best-effort pretty JSON formatting.
  String prettyJson(dynamic data) {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(sanitizeData(data));
  }
}

