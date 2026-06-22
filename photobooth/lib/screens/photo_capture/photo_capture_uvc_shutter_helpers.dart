/// Android [KeyEvent] codes that some USB/HDMI capture paths map to a physical shutter.
abstract final class UvcHardwareKeyCodes {
  static const int camera = 27;
  static const int focus = 80;
  static const int enter = 66;
  static const int dpadCenter = 23;
  static const int space = 62;
  static const int volumeUp = 24;
  static const int volumeDown = 25;

  static bool isShutterKey(int keyCode) {
    return keyCode == camera ||
        keyCode == focus ||
        keyCode == enter ||
        keyCode == dpadCenter ||
        keyCode == space ||
        keyCode == volumeUp ||
        keyCode == volumeDown;
  }
}

/// UVC hardware shutter handling (libuvc / serenegiant [IButtonCallback]).
///
/// Button id varies by body/capture card (0, 1, 2…). State is usually
/// `1` = pressed, `0` = released; some devices use `2` for press.
bool isUvcShutterCaptureEvent({
  required int button,
  required int state,
  bool acceptRelease = true,
}) {
  if (button < 0) return false;
  if (state == 1 || state == 2) return true;
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
  bool externalSignal = false,
}) {
  if (!externalSignal &&
      !isUvcShutterCaptureEvent(
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

bool shouldTriggerUvcShutterFromInterrupt({
  required DateTime? lastCaptureAt,
  DateTime? now,
}) {
  return shouldTriggerUvcShutterCapture(
    button: 0,
    state: 1,
    lastCaptureAt: lastCaptureAt,
    now: now,
    externalSignal: true,
  );
}

/// True while the DSLR body may still be pausing the HDMI feed after shutter.
bool isWithinUvcShutterGrace({
  required DateTime? graceUntil,
  DateTime? now,
}) {
  if (graceUntil == null) return false;
  return (now ?? DateTime.now()).isBefore(graceUntil);
}

/// Ignore spurious texture churn on connect; still allow HDMI pause after warmup.
bool shouldIgnoreUvcPreviewInterrupt({
  required bool holdLiveFeedClosed,
  required bool previewWarmupActive,
  required String? reason,
  required bool phaseIsLive,
}) {
  if (holdLiveFeedClosed || !phaseIsLive) return true;
  if (!previewWarmupActive) return false;
  final lower = reason?.toLowerCase() ?? '';
  return lower.contains('surface');
}
