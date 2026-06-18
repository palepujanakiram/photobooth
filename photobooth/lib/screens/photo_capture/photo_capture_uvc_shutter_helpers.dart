/// UVC hardware shutter handling (libuvc / serenegiant [IButtonCallback]).
///
/// Button id is usually `1` (shutter); some HDMI bridges use `0`.
/// State `1` = pressed, `0` = released. Some Canon bodies only report release.
bool isUvcShutterCaptureEvent({
  required int button,
  required int state,
  bool acceptRelease = true,
}) {
  final isShutterButton = button == 1 || button == 0;
  if (!isShutterButton) return false;
  if (state == 1) return true;
  return acceptRelease && state == 0;
}

/// Minimum gap between UVC shutter captures (press + release on same click).
const Duration kUvcShutterDebounce = Duration(milliseconds: 900);

bool shouldTriggerUvcShutterCapture({
  required int button,
  required int state,
  required DateTime? lastCaptureAt,
  DateTime? now,
  bool acceptRelease = true,
}) {
  if (!isUvcShutterCaptureEvent(
    button: button,
    state: state,
    acceptRelease: acceptRelease,
  )) {
    return false;
  }
  final instant = now ?? DateTime.now();
  if (lastCaptureAt != null &&
      instant.difference(lastCaptureAt) < kUvcShutterDebounce) {
    return false;
  }
  return true;
}
