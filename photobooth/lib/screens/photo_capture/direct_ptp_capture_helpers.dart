import '../../models/strip_models.dart';
import '../../services/direct_ptp_camera_service.dart';
import '../../utils/app_strings.dart';
import '../../utils/capture_session_kind.dart';
import '../../utils/constants.dart';

/// How many stills the native screen should collect for [kind].
int directPtpShotCountFor(CaptureSessionKind kind) =>
    kind.classicShotCount ?? 1;

/// Pose countdown for [kind], in seconds.
///
/// Read from [AppConstants] and passed to the native screen rather than
/// duplicated in Kotlin, so booth timing stays defined in one place.
int directPtpCountdownSecondsFor(CaptureSessionKind kind) => kind.isClassic
    ? AppConstants.kFlashbackCaptureCountdownSeconds
    : AppConstants.kCaptureCountdownSeconds;

/// Seconds between strip shots for guests to rearrange.
int get directPtpBetweenShotSeconds =>
    AppConstants.kFlashbackBetweenShotRearrangeDuration.inSeconds;

/// Operator-facing guidance for a native capture failure.
///
/// Deliberately keyed on the stable error **code**, not the message: each code
/// implies a different physical action, and a booth attendant reading "capture
/// failed" learns nothing they can act on.
String directPtpErrorMessage(String? code, {String? fallback}) {
  switch (code) {
    case 'no_device':
      return 'No camera found. Check the USB cable and that the camera is '
          'switched on.';
    case 'permission_denied':
      return 'USB permission was refused. Reconnect the camera and allow '
          'access when prompted.';
    case 'card_unavailable':
      return 'No memory card in the camera, or it is full. Insert a card with '
          'free space.';
    case 'camera_busy':
      return 'The camera is busy finishing the previous photo. Try again in a '
          'moment.';
    case 'connect_failed':
      return 'Could not open the camera. Switch it off and on again, then '
          'retry.';
    case 'download_failed':
      return 'The photo was taken but could not be transferred. Check the '
          'cable and retry.';
    case 'capture_failed':
    default:
      return fallback?.trim().isNotEmpty == true
          ? fallback!
          : 'The camera did not take the photo. Please try again.';
  }
}

/// Whether [result] produced everything [kind] needs to move on.
///
/// A strip that comes back short is a failure, not a partial success: the look
/// picker composes a fixed number of cells, and handing it three of four shots
/// produces a broken print rather than a smaller one.
bool directPtpResultIsUsable(
  DirectPtpCaptureResult result,
  CaptureSessionKind kind,
) {
  if (result.status != DirectPtpCaptureStatus.completed) return false;
  return result.shots.length >= directPtpShotCountFor(kind);
}

/// Subtitle shown above the native viewfinder for [kind].
///
/// Sourced from [AppStrings] so the native screen shows the same words as the
/// Flutter one — switching between them should be invisible to a guest.
String directPtpSubtitleFor(CaptureSessionKind kind) => switch (kind) {
      CaptureSessionKind.classicFourShot => AppStrings.flashbackCaptureSubtitle,
      CaptureSessionKind.classicOneShot =>
        AppStrings.flashbackCaptureSubtitleSingle,
      CaptureSessionKind.fotoZen => AppStrings.poseSubtitleDefault,
    };

/// Sanity bound on the strip length the native side is asked for.
///
/// Guards the one direction that silently corrupts output: asking for more
/// shots than the strip can hold would have the guest pose for photos that are
/// then discarded.
int clampDirectPtpShotCount(int requested) =>
    requested.clamp(1, kStripShotCount);
