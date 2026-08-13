import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/photo_capture/photo_capture_flashback_auto_helpers.dart';
import 'package:photobooth/utils/constants.dart';

void main() {
  group('captureCountdownSecondsForMode', () {
    test('Classic 1-shot and 4-shot use 10s; AI uses 5s', () {
      expect(
        captureCountdownSecondsForMode(isFlashbackMultiShot: true),
        10,
      );
      expect(
        captureCountdownSecondsForMode(
          isFlashbackMultiShot: true,
          acceptedShotCount: 1,
        ),
        10,
      );
      expect(
        captureCountdownSecondsForMode(
          isFlashbackMultiShot: true,
          acceptedShotCount: 3,
        ),
        AppConstants.kFlashbackFollowOnCountdownSeconds,
      );
      expect(
        captureCountdownSecondsForMode(isFlashbackMultiShot: false),
        AppConstants.kCaptureCountdownSeconds,
      );
      expect(AppConstants.kFlashbackCaptureCountdownSeconds, 10);
      expect(AppConstants.kFlashbackFollowOnCountdownSeconds, 10);
    });
  });

  group('flashbackSidecarStillPrepareAtSecond', () {
    test('all Classic shots prepare mid-countdown at second 4', () {
      expect(
        flashbackSidecarStillPrepareAtSecond(acceptedShotCount: 0),
        4,
      );
      expect(
        flashbackSidecarStillPrepareAtSecond(
          acceptedShotCount: 2,
          countdownSeconds: 10,
        ),
        4,
      );
      expect(
        flashbackSidecarStillPrepareAtSecond(acceptedShotCount: 1),
        AppConstants.kFlashbackSidecarStillPrepareAtSecond,
      );
      expect(AppConstants.kFlashbackSidecarStillPrepareWait.inSeconds, 3);
    });
  });

  group('flashbackShotReviewHoldDuration', () {
    test('1-shot brief; mid-strip 8s rearrange; last shot short', () {
      expect(
        flashbackShotReviewHoldDuration(
          acceptedShotCountBeforeThis: 0,
          total: 1,
        ),
        const Duration(milliseconds: 600),
      );
      expect(
        flashbackShotReviewHoldDuration(
          acceptedShotCountBeforeThis: 0,
          total: 4,
        ),
        AppConstants.kFlashbackBetweenShotRearrangeDuration,
      );
      expect(
        flashbackShotReviewHoldDuration(
          acceptedShotCountBeforeThis: 1,
          total: 4,
        ),
        const Duration(seconds: 8),
      );
      expect(
        flashbackShotReviewHoldDuration(
          acceptedShotCountBeforeThis: 3,
          total: 4,
        ),
        AppConstants.kFlashbackLastShotReviewDuration,
      );
      expect(AppConstants.kFlashbackBetweenShotRearrangeDuration.inSeconds, 8);
    });
  });

  group('shouldShowClassicBetweenShotReadyBanner', () {
    test('shows mid-strip while camera not ready', () {
      expect(
        shouldShowClassicBetweenShotReadyBanner(
          isFourShot: true,
          acceptedCount: 1,
          total: 4,
          hasCapturedPhoto: false,
          isCountingDown: false,
          isCapturing: false,
          cameraReadyForCapture: false,
          acceptingShot: false,
        ),
        isTrue,
      );
    });

    test('hides during countdown, review, or when ready', () {
      expect(
        shouldShowClassicBetweenShotReadyBanner(
          isFourShot: true,
          acceptedCount: 1,
          total: 4,
          hasCapturedPhoto: false,
          isCountingDown: true,
          isCapturing: false,
          cameraReadyForCapture: false,
          acceptingShot: false,
        ),
        isFalse,
      );
      expect(
        shouldShowClassicBetweenShotReadyBanner(
          isFourShot: true,
          acceptedCount: 1,
          total: 4,
          hasCapturedPhoto: false,
          isCountingDown: false,
          isCapturing: false,
          cameraReadyForCapture: true,
          acceptingShot: false,
        ),
        isFalse,
      );
      expect(
        shouldShowClassicBetweenShotReadyBanner(
          isFourShot: true,
          acceptedCount: 0,
          total: 4,
          hasCapturedPhoto: false,
          isCountingDown: false,
          isCapturing: false,
          cameraReadyForCapture: false,
          acceptingShot: true,
        ),
        isFalse,
      );
    });
  });

  group('shouldSoftFailHdmiMaskStall', () {
    test('true when mask stuck after countdown', () {
      expect(
        shouldSoftFailHdmiMaskStall(
          maskArmedOrPrep: true,
          captureInFlight: false,
          isCapturing: false,
          isCountingDown: false,
        ),
        isTrue,
      );
    });

    test('false while counting or shutter in flight', () {
      expect(
        shouldSoftFailHdmiMaskStall(
          maskArmedOrPrep: true,
          captureInFlight: false,
          isCapturing: false,
          isCountingDown: true,
        ),
        isFalse,
      );
      expect(
        shouldSoftFailHdmiMaskStall(
          maskArmedOrPrep: true,
          captureInFlight: true,
          isCapturing: false,
          isCountingDown: false,
        ),
        isFalse,
      );
      expect(
        shouldSoftFailHdmiMaskStall(
          maskArmedOrPrep: false,
          captureInFlight: false,
          isCapturing: false,
          isCountingDown: false,
        ),
        isFalse,
      );
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

    test('Classic 1-shot blocks a second auto pose after one capture started', () {
      expect(
        shouldAutoStartFlashbackCountdown(
          isFlashbackMultiShot: true,
          stripFinishing: false,
          navigatingAway: false,
          hasCapturedPhoto: false,
          isCountingDown: false,
          isCapturing: false,
          acceptedShotCount: 0,
          multiShotTotal: 1,
          cameraReadyForCapture: true,
          isSingleShot: true,
          singleShotCapturesStarted: 0,
        ),
        isTrue,
      );
      expect(
        shouldAutoStartFlashbackCountdown(
          isFlashbackMultiShot: true,
          stripFinishing: false,
          navigatingAway: false,
          hasCapturedPhoto: false,
          isCountingDown: false,
          isCapturing: false,
          acceptedShotCount: 0,
          multiShotTotal: 1,
          cameraReadyForCapture: true,
          isSingleShot: true,
          singleShotCapturesStarted: 1,
        ),
        isFalse,
      );
      expect(
        shouldAutoStartFlashbackCountdown(
          isFlashbackMultiShot: true,
          stripFinishing: false,
          navigatingAway: false,
          hasCapturedPhoto: false,
          isCountingDown: false,
          isCapturing: false,
          acceptedShotCount: 0,
          multiShotTotal: 4,
          cameraReadyForCapture: true,
          awaitGuestStart: true,
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

  group('flashbackReviewHoldAlreadyScheduled', () {
    test('true when timer or deadline is set', () {
      expect(
        flashbackReviewHoldAlreadyScheduled(
          timerActive: true,
          hasDeadline: false,
        ),
        isTrue,
      );
      expect(
        flashbackReviewHoldAlreadyScheduled(
          timerActive: false,
          hasDeadline: true,
        ),
        isTrue,
      );
      expect(
        flashbackReviewHoldAlreadyScheduled(
          timerActive: false,
          hasDeadline: false,
        ),
        isFalse,
      );
    });
  });

  group('flashbackReviewSecondsRemaining', () {
    test('floors remaining seconds and never goes negative', () {
      final now = DateTime.utc(2026, 1, 1, 12, 0, 0);
      expect(
        flashbackReviewSecondsRemaining(
          endsAt: now.add(const Duration(seconds: 8)),
          now: now,
        ),
        8,
      );
      expect(
        flashbackReviewSecondsRemaining(
          endsAt: now.add(const Duration(milliseconds: 1500)),
          now: now,
        ),
        1,
      );
      expect(
        flashbackReviewSecondsRemaining(
          endsAt: now.subtract(const Duration(seconds: 2)),
          now: now,
        ),
        0,
      );
    });
  });
}
