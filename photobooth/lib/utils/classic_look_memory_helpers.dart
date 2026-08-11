/// Whether Pick-a-look should skip background print-twin warm ([refreshComposePreview]).
///
/// Strip-quality JPEG data URLs + Dart `image` bake in a compute isolate has
/// LMK-killed 4GB Android TV Mini PCs right after looks load. ColorFilter
/// browse stays instant; Continue still composes on demand.
bool shouldDeferClassicComposePreviewWarm({
  required List<String> imageDataUrls,
  int largePayloadChars = 700000,
}) {
  if (imageDataUrls.length >= 4) return true;
  var total = 0;
  for (final url in imageDataUrls) {
    total += url.length;
    if (total >= largePayloadChars) return true;
  }
  return false;
}

/// Long-edge cap for look bake uploads — tighter when payloads are heavy.
int classicLookBakeMaxEdge({
  required List<String> imageDataUrls,
  int fullEdge = 2400,
  int compactEdge = 1600,
  int largePayloadChars = 700000,
}) {
  if (imageDataUrls.length >= 4) return compactEdge;
  var total = 0;
  for (final url in imageDataUrls) {
    total += url.length;
    if (total >= largePayloadChars) return compactEdge;
  }
  return fullEdge;
}
