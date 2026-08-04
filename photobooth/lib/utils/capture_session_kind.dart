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

  /// Classic: four stills → look picker (dual 2×6 strip).
  classicFourShot,
}

extension CaptureSessionKindX on CaptureSessionKind {
  bool get isClassic =>
      this == CaptureSessionKind.classicOneShot ||
      this == CaptureSessionKind.classicFourShot;

  bool get isClassicOneShot => this == CaptureSessionKind.classicOneShot;

  bool get isClassicFourShot => this == CaptureSessionKind.classicFourShot;

  bool get isFotoZen => this == CaptureSessionKind.fotoZen;

  /// Strip length for Classic; `null` for FotoZen (not a strip session).
  int? get classicShotCount => switch (this) {
        CaptureSessionKind.fotoZen => null,
        CaptureSessionKind.classicOneShot => 1,
        CaptureSessionKind.classicFourShot => kStripShotCount,
      };

  ClassicShotMode? get classicShotMode => switch (this) {
        CaptureSessionKind.fotoZen => null,
        CaptureSessionKind.classicOneShot => ClassicShotMode.single6x4,
        CaptureSessionKind.classicFourShot => ClassicShotMode.fourShot,
      };

  static CaptureSessionKind fromClassicShotMode(ClassicShotMode mode) {
    return mode.isSingle6x4
        ? CaptureSessionKind.classicOneShot
        : CaptureSessionKind.classicFourShot;
  }
}
