import '../models/strip_models.dart';
import 'classic_shot_mode.dart';

/// Which POSE flow this [PhotoCaptureScreen] is running.
///
/// Single constructor source of truth — never re-derived from subtitles,
/// SharedPreferences, or leftover process state (that caused Android TV
/// FotoZen / 1-shot to run the 4-shot remount loop).
enum CaptureSessionKind {
  /// AI FotoZen: one still → theme selection.
  fotoZen,

  /// Classic: one still → look picker (6×4 / 4×6).
  classicOneShot,

  /// Classic: three stills → look picker (dual 2×6 strip).
  classicThreeShot,

  /// Classic: four stills → look picker (dual 2×6 strip).
  classicFourShot,
}

extension CaptureSessionKindX on CaptureSessionKind {
  bool get isClassic =>
      this == CaptureSessionKind.classicOneShot ||
      this == CaptureSessionKind.classicThreeShot ||
      this == CaptureSessionKind.classicFourShot;

  bool get isClassicOneShot => this == CaptureSessionKind.classicOneShot;

  bool get isClassicThreeShot => this == CaptureSessionKind.classicThreeShot;

  bool get isClassicFourShot => this == CaptureSessionKind.classicFourShot;

  /// Any 2×6 strip session (3- or 4-shot). Use this — not
  /// [isClassicFourShot] — for "Classic, but not the 1-shot FSM" branches.
  bool get isClassicStrip => isClassicThreeShot || isClassicFourShot;

  /// Alias of [isClassicStrip] (main naming).
  bool get isClassicMultiShot => isClassicStrip;

  bool get isFotoZen => this == CaptureSessionKind.fotoZen;

  /// Strip length for Classic; `null` for FotoZen (not a strip session).
  int? get classicShotCount => switch (this) {
        CaptureSessionKind.fotoZen => null,
        CaptureSessionKind.classicOneShot => 1,
        CaptureSessionKind.classicThreeShot => kStripShotCountThree,
        CaptureSessionKind.classicFourShot => kStripShotCount,
      };

  ClassicShotMode? get classicShotMode => switch (this) {
        CaptureSessionKind.fotoZen => null,
        CaptureSessionKind.classicOneShot => ClassicShotMode.single6x4,
        CaptureSessionKind.classicThreeShot => ClassicShotMode.threeShot,
        CaptureSessionKind.classicFourShot => ClassicShotMode.fourShot,
      };

  static CaptureSessionKind fromClassicShotMode(ClassicShotMode mode) {
    return switch (mode) {
      ClassicShotMode.single6x4 => CaptureSessionKind.classicOneShot,
      ClassicShotMode.threeShot => CaptureSessionKind.classicThreeShot,
      ClassicShotMode.fourShot => CaptureSessionKind.classicFourShot,
    };
  }
}
