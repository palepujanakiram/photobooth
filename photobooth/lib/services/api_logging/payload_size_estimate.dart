import 'dart:convert';

/// Approximate serialized size for API debug logs (avoids huge [jsonEncode] on maps).
int? estimatePayloadSizeForLogging(dynamic data) {
  if (data == null) return null;
  if (data is String) return data.length;
  if (data is List<int>) return data.length;
  final mapSize = _estimateMapPayloadSize(data);
  if (mapSize != null) return mapSize;
  return _estimateJsonPayloadSize(data);
}

int? _estimateMapPayloadSize(dynamic data) {
  if (data is! Map) return null;
  final slug = data['userImageUrl'];
  if (slug is! String || slug.length <= 8192) return null;
  var total = 64;
  for (final e in data.entries) {
    if (e.key == 'userImageUrl' && e.value is String) {
      total += (e.value as String).length;
    } else {
      try {
        total += jsonEncode({e.key: e.value}).length;
      } catch (_) {
        total += 64;
      }
    }
  }
  return total;
}

int? _estimateJsonPayloadSize(dynamic data) {
  if (data is! Map && data is! List) return null;
  try {
    return jsonEncode(data).length;
  } catch (_) {
    return null;
  }
}
