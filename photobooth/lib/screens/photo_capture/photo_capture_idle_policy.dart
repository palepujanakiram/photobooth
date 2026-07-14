/// POSE screen idle reset: return to Terms after sustained inactivity.
class CaptureScreenIdleInput {
  const CaptureScreenIdleInput({
    required this.isNavigatingAway,
    required this.isCapturing,
    required this.isUploading,
    required this.isCountingDown,
    required this.appInForeground,
    this.isWaitingForPhoneUpload = false,
  });

  final bool isNavigatingAway;
  final bool isCapturing;
  final bool isUploading;
  final bool isCountingDown;
  final bool appInForeground;

  /// Guest is scanning/uploading via QR — do not idle-reset mid-wait.
  final bool isWaitingForPhoneUpload;
}

/// Whether the POSE idle timer may run (live feed or captured-still review).
bool captureScreenIdleTimerShouldRun(CaptureScreenIdleInput input) {
  if (input.isNavigatingAway) return false;
  if (!input.appInForeground) return false;
  if (input.isWaitingForPhoneUpload) return false;
  if (input.isCapturing || input.isUploading || input.isCountingDown) {
    return false;
  }
  return true;
}
