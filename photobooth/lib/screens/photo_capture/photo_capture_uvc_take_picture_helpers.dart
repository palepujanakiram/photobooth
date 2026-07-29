/// Whether [source] came from a physical DSLR / UVC shutter (not the UI button).
bool isUvcShutterCaptureSource(String source) {
  return source == 'preview_interrupt' ||
      source == 'uvc_button' ||
      source.startsWith('android_key_');
}

/// Raster [toImage] of the UVC Texture yields display-sized mush (~500–700px).
/// Never fall back — fail the shot so the guest retakes a real HDMI frame.
bool uvcAllowsRasterFallback(String source) {
  return false;
}

/// Single plugin capture; DSLR HDMI pause needs one long wait, not retries.
int uvcTakePictureAttemptsForSource(String source) {
  return 1;
}
