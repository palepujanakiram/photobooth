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
        ClassicShotMode.threeShot => 3,
        ClassicShotMode.single6x4 => 1,
      };

  bool get isSingle6x4 => this == ClassicShotMode.single6x4;

  bool get isMultiStrip =>
      this == ClassicShotMode.fourShot || this == ClassicShotMode.threeShot;
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
