import 'dart:convert';
import 'dart:typed_data';

import 'exceptions.dart';

/// Server rules for `PATCH /api/sessions/:id` body field `userImageUrl`.
class SessionUserImageValidation {
  SessionUserImageValidation._();

  /// Maximum size of the full `data:...;base64,...` string sent in JSON (conservative cap).
  static const int maxDataUrlCharacterLength = 8 * 1024 * 1024;

  /// Maximum decoded image bytes (after base64 decode of the payload segment).
  static const int maxDecodedPayloadBytes = 8 * 1024 * 1024;

  static final RegExp _dataUrlPattern = RegExp(
    r'^data:(image/(?:jpeg|png|webp));base64,([A-Za-z0-9+/=\s]+)\s*$',
    caseSensitive: false,
  );

  /// Throws [ApiException] if [dataUrl] is not acceptable for the session PATCH.
  static void assertValidForSessionPatch(String dataUrl) {
    final trimmed = dataUrl.trim();
    if (trimmed.isEmpty) {
      throw ApiException('Photo data is empty.');
    }
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      throw ApiException(
        'Photo must be a data: URL (image/jpeg, png, or webp), not an HTTP link.',
      );
    }
    if (!trimmed.startsWith('data:image/')) {
      throw ApiException(
        'Photo must be a data:image/...;base64,... URL (not raw base64 or a file path).',
      );
    }

    final match = _dataUrlPattern.firstMatch(trimmed);
    if (match == null) {
      throw ApiException(
        'Photo must be data:image/jpeg, data:image/png, or data:image/webp with base64 payload.',
      );
    }

    if (trimmed.length > maxDataUrlCharacterLength) {
      throw ApiException(
        'Photo is too large to upload (over ${maxDataUrlCharacterLength ~/ (1024 * 1024)} MB as data URL). '
        'Try a smaller capture or lower resolution.',
      );
    }

    final b64 = match.group(2)!.replaceAll(RegExp(r'\s'), '');
    late final Uint8List decoded;
    try {
      decoded = base64Decode(b64);
    } on FormatException {
      throw ApiException('Photo data URL has invalid base64 payload.');
    }

    if (decoded.length > maxDecodedPayloadBytes) {
      throw ApiException(
        'Decoded photo exceeds server limit (${maxDecodedPayloadBytes ~/ (1024 * 1024)} MB).',
      );
    }
  }
}
