import 'app_strings.dart';
import 'capture_session_kind.dart';
import 'classic_shot_mode.dart';

/// Maps experience CTA → POSE session kind.
CaptureSessionKind captureSessionKindForClassic(ClassicShotMode mode) {
  return CaptureSessionKindX.fromClassicShotMode(mode);
}

/// Subtitle under POSE for the given Classic mode.
String classicPoseSubtitle(ClassicShotMode mode) {
  return mode.isSingle6x4
      ? AppStrings.flashbackCaptureSubtitleSingle
      : AppStrings.flashbackCaptureSubtitle;
}
