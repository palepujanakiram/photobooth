import '../models/strip_models.dart';

/// Classic (FotoFlashback) shot count chosen on the experience screen.
enum ClassicShotMode {
  /// Default: four poses → dual 2×6 strip looks.
  fourShot,

  /// One pose → landscape 6×4 print (no strip frames).
  single6x4,
}

extension ClassicShotModeX on ClassicShotMode {
  int get shotCount => switch (this) {
        ClassicShotMode.fourShot => kStripShotCount,
        ClassicShotMode.single6x4 => 1,
      };

  bool get isSingle6x4 => this == ClassicShotMode.single6x4;
}
