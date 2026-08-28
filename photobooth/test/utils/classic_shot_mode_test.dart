import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/strip_models.dart';
import 'package:photobooth/utils/capture_session_kind.dart';
import 'package:photobooth/utils/classic_shot_mode.dart';

void main() {
  test('ClassicShotMode defaults to four-shot strip count', () {
    expect(ClassicShotMode.fourShot.shotCount, kStripShotCount);
    expect(ClassicShotMode.threeShot.shotCount, 3);
    expect(ClassicShotMode.single6x4.shotCount, 1);
    expect(ClassicShotMode.fourShot.isSingle6x4, isFalse);
    expect(ClassicShotMode.single6x4.isSingle6x4, isTrue);
    expect(ClassicShotMode.threeShot.isMultiStrip, isTrue);
  });

  test('threeShot is a strip mode with three poses', () {
    expect(ClassicShotMode.threeShot.shotCount, kStripShotCountThree);
    expect(ClassicShotMode.threeShot.shotCount, 3);
    expect(ClassicShotMode.threeShot.isSingle6x4, isFalse);
    expect(ClassicShotMode.threeShot.isStrip, isTrue);
    expect(ClassicShotMode.fourShot.isStrip, isTrue);
    expect(ClassicShotMode.single6x4.isStrip, isFalse);
    expect(ClassicShotMode.threeShot.shotCountLabel, '3');
  });

  test('classicStripShotModeForCount maps counts back to modes', () {
    expect(classicStripShotModeForCount(1), ClassicShotMode.single6x4);
    expect(classicStripShotModeForCount(3), ClassicShotMode.threeShot);
    expect(classicStripShotModeForCount(4), ClassicShotMode.fourShot);
    // Anything unexpected keeps the historical four-shot strip.
    expect(classicStripShotModeForCount(0), ClassicShotMode.fourShot);
    expect(classicStripShotModeForCount(9), ClassicShotMode.fourShot);
  });

  test('fewer shots means taller cells on the same fixed 2x6 print', () {
    // HAMA: 600×1800, 10px margins + 10px gutters → 4-shot 580×437.5.
    expect(
      ClassicShotMode.fourShot.stripCellAspectRatio,
      closeTo(580 / 437.5, 0.0001),
    );
    expect(
      ClassicShotMode.threeShot.stripCellAspectRatio,
      closeTo(580 / (1760 / 3), 0.0001),
    );
    // 4-shot cells are landscape; 3-shot cells are near square (taller).
    expect(ClassicShotMode.fourShot.stripCellAspectRatio, greaterThan(1));
    expect(ClassicShotMode.threeShot.stripCellAspectRatio, lessThan(1));
    expect(
      ClassicShotMode.threeShot.stripCellAspectRatio,
      lessThan(ClassicShotMode.fourShot.stripCellAspectRatio),
    );
  });

  test('isValidClassicComposeShotCount accepts 1, 3 and 4 only', () {
    expect(isValidClassicComposeShotCount(1), isTrue);
    expect(isValidClassicComposeShotCount(3), isTrue);
    expect(isValidClassicComposeShotCount(4), isTrue);
    expect(isValidClassicComposeShotCount(0), isFalse);
    expect(isValidClassicComposeShotCount(2), isFalse);
    expect(isValidClassicComposeShotCount(5), isFalse);
    expect(kClassicStripShotCounts, [3, 4]);
  });

  test('plain_6x4 is no longer a strip frame or sheet layout', () {
    expect(kStripFrameIds.contains('plain_6x4'), isFalse);
    expect(isStripSheetLayout('plain_6x4'), isFalse);
    expect(isStripSheetLayout('romantic'), isTrue);
  });

  test('classic shot modes normalize and map to session kinds', () {
    expect(normalizeClassicShotModes([4, 1, 9]), [1, 4]);
    expect(normalizeClassicShotModes(null), [1, 3, 4]);
    expect(normalizeClassicShotModes([3.7, ' 1 ', 4]), [1, 4]);
    expect(classicShotModeForCount(3), ClassicShotMode.threeShot);
    expect(classicShotModeForCount(2), isNull);
    expect(
      CaptureSessionKindX.fromClassicShotMode(ClassicShotMode.threeShot),
      CaptureSessionKind.classicThreeShot,
    );
    expect(CaptureSessionKind.classicThreeShot.isClassicMultiShot, isTrue);
  });
}
