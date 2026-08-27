import '../models/strip_models.dart';

/// Classic (FotoFlashback) shot count chosen on the experience screen.
enum ClassicShotMode {
  /// Four poses → dual 2×6 strip looks.
  fourShot,

  /// Three poses → dual 2×6 strip (taller cells).
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

  /// Alias of [isStrip] (main naming).
  bool get isMultiStrip => isStrip;

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

/// Allowed Classic shot counts from kiosk bind (`classicShotModes`).
List<int> normalizeClassicShotModes(Iterable<dynamic>? raw) {
  const allowed = {1, 3, 4};
  final seen = <int>{};
  if (raw != null) {
    for (final item in raw) {
      final n = item is int
          ? item
          : item is num
              ? item.round()
              : int.tryParse(item?.toString().trim() ?? '');
      if (n != null && allowed.contains(n)) seen.add(n);
    }
  }
  if (seen.isEmpty) return const [1, 3, 4];
  return [1, 3, 4].where(seen.contains).toList();
}

ClassicShotMode? classicShotModeForCount(int count) {
  return switch (count) {
    1 => ClassicShotMode.single6x4,
    3 => ClassicShotMode.threeShot,
    4 => ClassicShotMode.fourShot,
    _ => null,
  };
}
