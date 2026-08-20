/// Whether Pick-a-look should skip background print-twin warm entirely.
///
/// 4-shot / huge strip-quality payloads: idle bake+compose freezes Mini PC
/// look UI (and can LMK). Continue still composes on demand with a timeout.
bool shouldDeferClassicComposePreviewWarm({
  required List<String> imageDataUrls,
  bool captureUploadsAlreadyCompact = false,
  int largePayloadChars = 700000,
}) {
  // 4-shot browse stays on Flutter ColorFilter — idle compose warm flickers the
  // preview (banner layout shifts + full rebuilds on every filter/sticker tap).
  // Continue still composes on demand; Direct PTP compact skips re-compact.
  if (imageDataUrls.length >= 4) return true;
  return classicImagePayloadIsLarge(
    imageDataUrls: imageDataUrls,
    largePayloadChars: largePayloadChars,
  );
}

/// True when [filePaths] are Direct PTP display derivatives (1600/q90 on disk).
bool classicCaptureFilesAreCompactDisplayDerivatives({
  required List<String> filePaths,
}) {
  if (filePaths.isEmpty) return false;
  for (final path in filePaths) {
    if (!path.toLowerCase().endsWith('.display.jpg')) return false;
  }
  return true;
}

/// True when Continue should skip local Flutter look-bake and let the server
/// Sharp pipeline apply the selected filter id.
///
/// 4-shot / huge payloads: sequential print-size bake on Mini PC hangs before
/// `/strip/compose`. 1-shot: the same 2400 bake of a Canon EVF/JPEG plate can
/// sit on Continue for minutes; ColorFilter browse already matches the look.
bool shouldSkipClassicClientLookBake({
  required List<String> imageDataUrls,
  int largePayloadChars = 700000,
}) {
  if (imageDataUrls.length == 1) return true;
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
  if (imageDataUrls.length >= 4 ||
      classicImagePayloadIsLarge(
        imageDataUrls: imageDataUrls,
        largePayloadChars: largePayloadChars,
      )) {
    return compactEdge;
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

/// Default size at which `/strip/compose` should 1600/q90 compact first.
///
/// Tiny unit-test fixtures stay under this so fakeAsync compose tests skip
/// the isolate. Four Canon plates are well above it.
const int kClassicComposeCompactPayloadChars = 200000;

/// True when compose uploads are large enough to stall Mini PC Continue.
bool shouldCompactClassicComposeUploads({
  required List<String> imageDataUrls,
  bool captureUploadsAlreadyCompact = false,
  int largePayloadChars = kClassicComposeCompactPayloadChars,
}) {
  if (captureUploadsAlreadyCompact) return false;
  return classicImagePayloadIsLarge(
    imageDataUrls: imageDataUrls,
    largePayloadChars: largePayloadChars,
  );
}

/// Running length of strip shot data URLs, short-circuiting at [largePayloadChars].
bool classicImagePayloadIsLarge({
  required List<String> imageDataUrls,
  int largePayloadChars = 700000,
}) {
  var total = 0;
  for (final url in imageDataUrls) {
    total += url.length;
    if (total >= largePayloadChars) return true;
  }
  return false;
}
