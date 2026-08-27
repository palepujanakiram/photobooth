import '../models/strip_models.dart';

/// Classic (FotoFlashback) shot count chosen on the experience screen.
enum ClassicShotMode {
  /// Default: four poses → dual 2×6 strip looks.
  fourShot,

  /// Three poses → same dual 2×6 strip, taller cells.
  threeShot,

  /// One pose → single 6×4 / 4×6 print (orientation chosen separately).
  single6x4,
}

extension ClassicShotModeX on ClassicShotMode {
  int get shotCount => switch (this) {
        ClassicShotMode.fourShot => kStripShotCount,
        ClassicShotMode.threeShot => kStripShotCountThree,
        ClassicShotMode.single6x4 => 1,
      };

  bool get isSingle6x4 => this == ClassicShotMode.single6x4;

  /// Any 2×6 strip mode (3- or 4-shot) — the flows 1-shot must not enter.
  bool get isStrip => !isSingle6x4;

  /// Print cell aspect for this mode's 2×6 strip (1-shot has no strip cell).
  double get stripCellAspectRatio => stripCellAspectRatioForShots(shotCount);

  /// Stable route/log token (`1`, `3`, `4`).
  String get shotCountLabel => '$shotCount';
}

/// Strip mode for [shotCount]; anything but 3 falls back to the 4-shot strip.
ClassicShotMode classicStripShotModeForCount(int shotCount) {
  if (shotCount == 1) return ClassicShotMode.single6x4;
  if (shotCount == kStripShotCountThree) return ClassicShotMode.threeShot;
  return ClassicShotMode.fourShot;
}
