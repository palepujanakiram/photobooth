import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/utils/app_strings.dart';
import 'package:photobooth/utils/capture_session_kind.dart';
import 'package:photobooth/utils/classic_pose_mode_helpers.dart';
import 'package:photobooth/utils/classic_shot_mode.dart';

void main() {
  group('captureSessionKindForClassic', () {
    test('maps 1-shot and 4-shot', () {
      expect(
        captureSessionKindForClassic(ClassicShotMode.single6x4),
        CaptureSessionKind.classicOneShot,
      );
      expect(
        captureSessionKindForClassic(ClassicShotMode.fourShot),
        CaptureSessionKind.classicFourShot,
      );
    });
  });

  group('classicPoseSubtitle', () {
    test('1-shot explains 10s countdown', () {
      expect(
        classicPoseSubtitle(ClassicShotMode.single6x4),
        AppStrings.flashbackCaptureSubtitleSingle,
      );
    });

    test('4-shot explains 10s pose and 8s rearrange', () {
      expect(
        classicPoseSubtitle(ClassicShotMode.fourShot),
        AppStrings.flashbackCaptureSubtitle,
      );
      expect(AppStrings.flashbackCaptureSubtitle, contains('10s'));
      expect(AppStrings.flashbackCaptureSubtitle, contains('8s'));
    });
  });

  group('CaptureSessionKind', () {
    test('fotoZen is not classic and has no shot count', () {
      expect(CaptureSessionKind.fotoZen.isClassic, isFalse);
      expect(CaptureSessionKind.fotoZen.isFotoZen, isTrue);
      expect(CaptureSessionKind.fotoZen.isClassicOneShot, isFalse);
      expect(CaptureSessionKind.fotoZen.isClassicFourShot, isFalse);
      expect(CaptureSessionKind.fotoZen.classicShotCount, isNull);
      expect(CaptureSessionKind.fotoZen.classicShotMode, isNull);
    });

    test('classic kinds expose shot counts', () {
      expect(CaptureSessionKind.classicOneShot.isClassicOneShot, isTrue);
      expect(CaptureSessionKind.classicOneShot.isClassicFourShot, isFalse);
      expect(CaptureSessionKind.classicOneShot.isFotoZen, isFalse);
      expect(CaptureSessionKind.classicFourShot.isClassicFourShot, isTrue);
      expect(CaptureSessionKind.classicFourShot.isClassicOneShot, isFalse);
      expect(CaptureSessionKind.classicOneShot.classicShotCount, 1);
      expect(CaptureSessionKind.classicFourShot.classicShotCount, 4);
      expect(
        CaptureSessionKind.classicOneShot.classicShotMode,
        ClassicShotMode.single6x4,
      );
      expect(
        CaptureSessionKind.classicFourShot.classicShotMode,
        ClassicShotMode.fourShot,
      );
    });
  });
}
