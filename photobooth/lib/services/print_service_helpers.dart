import '../utils/secure_image_url.dart';

/// Absolute URL with `sessionId` for protected `/api/img/*` resources.
String resolveRemoteImageUrlForPrint(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return trimmed;

  final absolute = trimmed.startsWith('http://') || trimmed.startsWith('https://')
      ? trimmed
      : SecureImageUrl.absolutize(trimmed);
  return SecureImageUrl.withSessionId(absolute);
}
