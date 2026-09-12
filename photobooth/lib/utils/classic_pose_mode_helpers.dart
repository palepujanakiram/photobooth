import 'app_runtime_config.dart';
import 'app_strings.dart';
import 'capture_session_kind.dart';
import 'classic_pose_countdown.dart';
import 'classic_shot_mode.dart';

/// Maps experience CTA → POSE session kind.
CaptureSessionKind captureSessionKindForClassic(ClassicShotMode mode) {
  return CaptureSessionKindX.fromClassicShotMode(mode);
}

/// Subtitle under POSE for the given Classic mode.
String classicPoseSubtitle(ClassicShotMode mode, {int? poseSeconds}) {
  final seconds = normalizeClassicPoseCountdownSeconds(
    poseSeconds ?? AppRuntimeConfig.instance.classicPoseCountdownSeconds,
  );
  return switch (mode) {
    ClassicShotMode.single6x4 =>
      AppStrings.flashbackCaptureSubtitleSingleFor(seconds),
    ClassicShotMode.threeShot =>
      AppStrings.flashbackCaptureSubtitleThreeFor(seconds),
    ClassicShotMode.fourShot => AppStrings.flashbackCaptureSubtitleFor(seconds),
  };
}
