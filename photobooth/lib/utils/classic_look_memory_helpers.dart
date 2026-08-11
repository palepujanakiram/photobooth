/// Whether Pick-a-look should skip background print-twin warm entirely.
///
/// 4-shot / huge strip-quality payloads: idle bake+compose freezes Mini PC
/// look UI (and can LMK). Continue still composes on demand with a timeout.
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

/// True when Continue should skip local Flutter look-bake and let the server
/// Sharp pipeline apply the selected filter id.
///
/// Same trigger as [shouldDeferClassicComposePreviewWarm]: 4-shot / huge
/// payloads. Sequential print-size bake on Mini PC / web often OOMs or hangs
/// before `/strip/compose` is ever POSTed ("Couldn't build strip" with no
/// server log).
bool shouldSkipClassicClientLookBake({
  required List<String> imageDataUrls,
  int largePayloadChars = 700000,
}) {
  return shouldDeferClassicComposePreviewWarm(
    imageDataUrls: imageDataUrls,
    largePayloadChars: largePayloadChars,
  );
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
