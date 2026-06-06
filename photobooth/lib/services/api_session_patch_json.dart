import 'dart:convert';

import '../utils/exceptions.dart';
import 'api_json_scan_utils.dart';

/// Index of the closing `"` for a JSON string starting at [openQuoteIndex] (`"` itself).
/// Handles standard escapes (`\"`, `\\`, `\uXXXX`, etc.). Returns -1 if not found.
int jsonStringCloseQuoteIndex(String raw, int openQuoteIndex) {
  var i = openQuoteIndex + 1;
  while (i < raw.length) {
    final ch = raw[i];
    if (ch == r'\') {
      if (i + 1 >= raw.length) return -1;
      final n = raw[i + 1];
      if (n == 'u' && i + 6 <= raw.length) {
        i += 6;
        continue;
      }
      i += 2;
      continue;
    }
    if (ch == '"') return i;
    i++;
  }
  return -1;
}

/// Remove echoed `userImageUrl` string value from raw JSON so [jsonDecode] avoids a multi‑MB field.
/// Uses JSON-aware scanning so escaped `"` inside the value does not truncate early.
String stripEchoedUserImageUrlField(String raw) {
  const key = '"userImageUrl"';
  final keyIdx = raw.indexOf(key);
  if (keyIdx < 0) return raw;

  final colon = raw.indexOf(':', keyIdx + key.length);
  if (colon < 0) return raw;

  final valueStart = ApiJsonScanUtils.skipLeadingWhitespace(raw, colon + 1);
  if (valueStart >= raw.length || raw[valueStart] != '"') return raw;

  final valueCloseIdx = jsonStringCloseQuoteIndex(raw, valueStart);
  if (valueCloseIdx < 0) return raw;

  final removeStart = ApiJsonScanUtils.indexOfLeadingCommaBefore(raw, keyIdx);
  final removeEnd = ApiJsonScanUtils.endIndexAfterJsonValue(raw, valueCloseIdx);
  return raw.substring(0, removeStart) + raw.substring(removeEnd);
}

/// Dio may get **HTTP 200 + HTML** (proxy error page, missing route behind gateway).
/// [jsonDecode] then fails with `Unexpected token '<'…` — surface a clear [ApiException] instead.
void assertSessionBodyLooksLikeJson(String raw, String endpointDescription) {
  final s = raw.trimLeft();
  if (s.isEmpty) return;
  final head = s.length > 9 ? s.substring(0, 9).toLowerCase() : s.toLowerCase();
  if (head.startsWith('<!doctype') || head.startsWith('<html')) {
    throw ApiException(
      'Server returned HTML instead of JSON for $endpointDescription. '
      'Check the API is deployed and the path is correct.',
    );
  }
  if (s.startsWith('<')) {
    throw ApiException(
      'Server returned HTML instead of JSON for $endpointDescription. '
      'Check the API is deployed and the path is correct (got a web page, not JSON).',
    );
  }
  if (!s.startsWith('{') && !s.startsWith('[')) {
    throw ApiException(
      'Server returned non-JSON for $endpointDescription. '
      'Expected a JSON object from the API.',
    );
  }
}

Map<String, dynamic> _decodeSessionPatchMap(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! Map) {
    throw const FormatException('Session PATCH: expected a JSON object');
  }
  final map = Map<String, dynamic>.from(decoded);
  map.remove('userImageUrl');
  return map;
}

/// Decode session PATCH JSON; server often echoes huge `userImageUrl`.
Map<String, dynamic> parseSessionPatchResponseJson(String raw) {
  assertSessionBodyLooksLikeJson(raw, 'PATCH /api/sessions/:sessionId');
  try {
    return _decodeSessionPatchMap(stripEchoedUserImageUrlField(raw));
  } on FormatException {
    try {
      return _decodeSessionPatchMap(raw);
    } on FormatException {
      throw ApiException(
        'Could not read session response from the server. '
        'If you recently changed API routes, confirm PATCH /api/sessions returns JSON.',
      );
    }
  }
}
