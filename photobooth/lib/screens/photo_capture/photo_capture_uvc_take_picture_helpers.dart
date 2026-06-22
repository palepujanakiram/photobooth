/// Whether [source] came from a physical DSLR / UVC shutter (not the UI button).
bool isUvcShutterCaptureSource(String source) {
  return source == 'preview_interrupt' ||
      source == 'uvc_button' ||
      source.startsWith('android_key_');
}

/// Raster [toImage] does not capture UVC Texture pixels reliably on Android.
bool uvcAllowsRasterFallback(String source) {
  return source == 'preview_interrupt';
}

/// Single plugin capture; DSLR HDMI pause needs one long wait, not retries.
int uvcTakePictureAttemptsForSource(String source) {
  return 1;
}
