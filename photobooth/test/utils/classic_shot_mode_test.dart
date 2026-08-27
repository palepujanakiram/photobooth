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

  test('plain_6x4 is no longer a strip frame or sheet layout', () {
    expect(kStripFrameIds.contains('plain_6x4'), isFalse);
    expect(isStripSheetLayout('plain_6x4'), isFalse);
    expect(isStripSheetLayout('romantic'), isTrue);
  });

  test('classic shot modes normalize and map to session kinds', () {
    expect(normalizeClassicShotModes([4, 1, 9]), [1, 4]);
    expect(normalizeClassicShotModes(null), [1, 3, 4]);
    expect(classicShotModeForCount(3), ClassicShotMode.threeShot);
    expect(
      CaptureSessionKindX.fromClassicShotMode(ClassicShotMode.threeShot),
      CaptureSessionKind.classicThreeShot,
    );
    expect(CaptureSessionKind.classicThreeShot.isClassicMultiShot, isTrue);
  });
}
