import '../utils/app_strings.dart';
import 'local_guest_media_write.dart';
import 'local_media_store.dart';
import 'session_deliverable_images.dart';

/// Local persist then, if still a data URL, upload so staff History can thumb.
///
/// Native kiosks write `/api/img/...` on disk (outbox syncs later). Web cannot
/// write disk, so [upload] stores the JPEG and returns a proxy path.
Future<String> persistClassicPrintDeliverable({
  required String sessionId,
  required String imageUrl,
  Future<String> Function(String source)? persistLocal,
  Future<String?> Function({
    required String sessionId,
    required String imageDataUrl,
  })? upload,
}) async {
  final trimmed = imageUrl.trim();
  if (trimmed.isEmpty) return trimmed;
  if (isSessionProxyImageUrl(trimmed)) return trimmed;

  var next = trimmed;
  if (persistLocal != null) {
    next = (await persistLocal(trimmed)).trim();
    if (isSessionProxyImageUrl(next)) return next;
  }

  final sid = sessionId.trim();
  if (sid.isEmpty ||
      upload == null ||
      !next.startsWith(AppStrings.dataImagePrefix)) {
    return next;
  }
  try {
    final stored = await upload(sessionId: sid, imageDataUrl: next);
    final proxy = stored?.trim() ?? '';
    if (isSessionProxyImageUrl(proxy)) return proxy;
  } catch (_) {
    // Fail-open: guest print still uses the data URL.
  }
  return next;
}

/// Default disk persist for Classic print JPEGs (`fotoflashback/` prefix).
Future<String> persistClassicPrintLocally(String source) {
  return persistGuestImageUrl(
    prefix: kGuestMediaPrefixFotoflashback,
    source: source,
    fetchBytes: guestMediaNetworkFetch(),
  );
}
