import 'local_media_store.dart';

/// True when [raw] is a Fly private-image proxy path (ingest + staff thumbs).
bool isSessionProxyImageUrl(Object? raw) {
  if (raw is! String) return false;
  final s = raw.trim();
  if (s.isEmpty || s.startsWith('data:')) return false;
  return s.contains(kApiImgPathPrefix);
}

/// Merges proxy `/api/img/...` strings from [existing] and [incoming], deduped.
List<String> mergeSessionProxyImageUrls(
  Iterable<dynamic> existing,
  Iterable<String> incoming, {
  int maxCount = 24,
}) {
  final out = <String>[];
  final seen = <String>{};
  void push(Object? item) {
    if (!isSessionProxyImageUrl(item)) return;
    final url = (item as String).trim();
    if (seen.contains(url)) return;
    seen.add(url);
    out.add(url);
  }

  for (final item in existing) {
    push(item);
    if (out.length >= maxCount) return out;
  }
  for (final item in incoming) {
    push(item);
    if (out.length >= maxCount) return out;
  }
  return out;
}
