import 'constants.dart';

/// Clamp Classic pose countdown to the kiosk admin range (5–15s, default 10).
///
/// Floor of 5 keeps Pi HDMI still-prep (fires at countdown 4) on the timeline.
int normalizeClassicPoseCountdownSeconds(int? raw) {
  const fallback = AppConstants.kFlashbackCaptureCountdownSeconds;
  if (raw == null) return fallback;
  if (raw < AppConstants.kClassicPoseCountdownMinSeconds) {
    return AppConstants.kClassicPoseCountdownMinSeconds;
  }
  if (raw > AppConstants.kClassicPoseCountdownMaxSeconds) {
    return AppConstants.kClassicPoseCountdownMaxSeconds;
  }
  return raw;
}
