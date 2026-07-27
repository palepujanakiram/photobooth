import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/photo_capture/photo_capture_flashback_auto_helpers.dart';
import 'package:photobooth/utils/constants.dart';

void main() {
  group('captureCountdownSecondsForMode', () {
    test('Classic uses 10s; AI uses 5s', () {
      expect(
        captureCountdownSecondsForMode(isFlashbackMultiShot: true),
        AppConstants.kFlashbackCaptureCountdownSeconds,
      );
      expect(
        captureCountdownSecondsForMode(isFlashbackMultiShot: false),
        AppConstants.kCaptureCountdownSeconds,
      );
      expect(AppConstants.kFlashbackCaptureCountdownSeconds, 10);
    });
  });

  group('shouldAutoStartFlashbackCountdown', () {
    test('starts when live and more shots remain', () {
      expect(
        shouldAutoStartFlashbackCountdown(
          isFlashbackMultiShot: true,
          stripFinishing: false,
          navigatingAway: false,
          hasCapturedPhoto: false,
          isCountingDown: false,
          isCapturing: false,
          acceptedShotCount: 1,
          multiShotTotal: 4,
          cameraReadyForCapture: true,
        ),
        isTrue,
      );
    });

    test('does not start during review or countdown', () {
      expect(
        shouldAutoStartFlashbackCountdown(
          isFlashbackMultiShot: true,
          stripFinishing: false,
          navigatingAway: false,
          hasCapturedPhoto: true,
          isCountingDown: false,
          isCapturing: false,
          acceptedShotCount: 0,
          multiShotTotal: 4,
          cameraReadyForCapture: true,
        ),
        isFalse,
      );
      expect(
        shouldAutoStartFlashbackCountdown(
          isFlashbackMultiShot: true,
          stripFinishing: false,
          navigatingAway: false,
          hasCapturedPhoto: false,
          isCountingDown: true,
          isCapturing: false,
          acceptedShotCount: 0,
          multiShotTotal: 4,
          cameraReadyForCapture: true,
        ),
        isFalse,
      );
    });

    test('stops after all shots accepted', () {
      expect(
        shouldAutoStartFlashbackCountdown(
          isFlashbackMultiShot: true,
          stripFinishing: false,
          navigatingAway: false,
          hasCapturedPhoto: false,
          isCountingDown: false,
          isCapturing: false,
          acceptedShotCount: 4,
          multiShotTotal: 4,
          cameraReadyForCapture: true,
        ),
        isFalse,
      );
    });
  });

  group('shouldScheduleFlashbackAutoAccept', () {
    test('schedules once when a still is ready for review', () {
      expect(
        shouldScheduleFlashbackAutoAccept(
          isFlashbackMultiShot: true,
          stripFinishing: false,
          navigatingAway: false,
          hasCapturedPhoto: true,
          isCapturing: false,
          autoAcceptAlreadyScheduled: false,
        ),
        isTrue,
      );
      expect(
        shouldScheduleFlashbackAutoAccept(
          isFlashbackMultiShot: true,
          stripFinishing: false,
          navigatingAway: false,
          hasCapturedPhoto: true,
          isCapturing: false,
          autoAcceptAlreadyScheduled: true,
        ),
        isFalse,
      );
    });
  });
}
