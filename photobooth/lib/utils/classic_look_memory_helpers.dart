/// Whether Pick-a-look should skip **immediate** print-twin warm on catalog load.
///
/// Large strip-quality JPEGs + bake in `compute()` LMK-killed 4GB Android TV when
/// warm ran the instant looks appeared. Idle warm (delayed / after look select)
/// is still allowed so Continue can reuse a ready compose.
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
///
/// Compact 1400 keeps DNP 4×6 acceptable while cutting Continue bake/upload time
/// vs full 2400 on Mini PC Classic stills.
int classicLookBakeMaxEdge({
  required List<String> imageDataUrls,
  int fullEdge = 2400,
  int compactEdge = 1400,
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

/// True when bake should run one shot per isolate (lower peak RAM on TV).
bool shouldBakeClassicLooksSequentially({
  required List<String> imageDataUrls,
}) {
  return imageDataUrls.length > 1 ||
      shouldDeferClassicComposePreviewWarm(imageDataUrls: imageDataUrls);
}
