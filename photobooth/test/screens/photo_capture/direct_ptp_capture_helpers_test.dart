import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/strip_models.dart';
import 'package:photobooth/screens/photo_capture/direct_ptp_capture_helpers.dart';
import 'package:photobooth/services/direct_ptp_camera_service.dart';
import 'package:photobooth/utils/app_strings.dart';
import 'package:photobooth/utils/capture_session_kind.dart';
import 'package:photobooth/utils/constants.dart';

DirectPtpCaptureResult _completed(int shots) => DirectPtpCaptureResult(
      status: DirectPtpCaptureStatus.completed,
      shots: List<DirectPtpShot>.generate(
        shots,
        (i) => DirectPtpShot(originalPath: '/o$i.JPG', displayPath: '/d$i.jpg'),
      ),
    );

void main() {
  group('shot count', () {
    test('FotoZen is a single shot', () {
      expect(directPtpShotCountFor(CaptureSessionKind.fotoZen), 1);
    });

    test('Classic one-shot is a single shot', () {
      expect(directPtpShotCountFor(CaptureSessionKind.classicOneShot), 1);
    });

    test('Classic four-shot matches the strip length', () {
      expect(
        directPtpShotCountFor(CaptureSessionKind.classicFourShot),
        kStripShotCount,
      );
    });

    test('the requested count is clamped to what a strip can hold', () {
      // Over-asking is the direction that silently wastes a guest's time: they
      // would pose for photos the strip then discards.
      expect(clampDirectPtpShotCount(99), kStripShotCount);
      expect(clampDirectPtpShotCount(0), 1);
      expect(clampDirectPtpShotCount(-3), 1);
      expect(clampDirectPtpShotCount(kStripShotCount), kStripShotCount);
    });
  });

  group('timing', () {
    test('Classic uses the flashback pose countdown', () {
      expect(
        directPtpCountdownSecondsFor(CaptureSessionKind.classicFourShot),
        AppConstants.kFlashbackCaptureCountdownSeconds,
      );
      expect(
        directPtpCountdownSecondsFor(CaptureSessionKind.classicOneShot),
        AppConstants.kFlashbackCaptureCountdownSeconds,
      );
    });

    test('FotoZen uses the shorter standard countdown', () {
      expect(
        directPtpCountdownSecondsFor(CaptureSessionKind.fotoZen),
        AppConstants.kCaptureCountdownSeconds,
      );
    });

    test('the rearrange gap comes from AppConstants, not a native default', () {
      // Timing must be defined once in Dart; the native screen is handed the
      // value so the two stacks cannot drift.
      expect(
        directPtpBetweenShotSeconds,
        AppConstants.kFlashbackBetweenShotRearrangeDuration.inSeconds,
      );
    });
  });

  group('subtitles', () {
    test('reuse the existing booth copy for each flow', () {
      expect(
        directPtpSubtitleFor(CaptureSessionKind.classicFourShot),
        AppStrings.flashbackCaptureSubtitle,
      );
      expect(
        directPtpSubtitleFor(CaptureSessionKind.classicOneShot),
        AppStrings.flashbackCaptureSubtitleSingle,
      );
      expect(
        directPtpSubtitleFor(CaptureSessionKind.fotoZen),
        AppStrings.poseSubtitleDefault,
      );
    });
  });

  group('directPtpErrorMessage', () {
    test('each code gives a distinct, actionable instruction', () {
      final messages = <String>{
        directPtpErrorMessage('no_device'),
        directPtpErrorMessage('permission_denied'),
        directPtpErrorMessage('card_unavailable'),
        directPtpErrorMessage('camera_busy'),
        directPtpErrorMessage('connect_failed'),
        directPtpErrorMessage('download_failed'),
      };
      // Distinct because each implies a different physical action; collapsing
      // any two would tell an attendant to do the wrong thing.
      expect(messages, hasLength(6));
    });

    test('the card message names the actual fix', () {
      expect(directPtpErrorMessage('card_unavailable'), contains('card'));
    });

    test('an unknown code falls back to the supplied detail', () {
      expect(
        directPtpErrorMessage('something_new', fallback: 'Lens cap on'),
        'Lens cap on',
      );
    });

    test('an unknown code with no detail still says something useful', () {
      final message = directPtpErrorMessage(null);
      expect(message, isNotEmpty);
      expect(message, contains('try again'));
    });

    test('a blank fallback does not produce an empty message', () {
      expect(directPtpErrorMessage('capture_failed', fallback: '   '),
          isNotEmpty);
    });
  });

  group('directPtpResultIsUsable', () {
    test('a full strip is usable', () {
      expect(
        directPtpResultIsUsable(
          _completed(kStripShotCount),
          CaptureSessionKind.classicFourShot,
        ),
        isTrue,
      );
    });

    test('a short strip is a failure, not a partial success', () {
      // The look picker composes a fixed number of cells; three of four shots
      // produces a broken print rather than a smaller one.
      expect(
        directPtpResultIsUsable(
          _completed(kStripShotCount - 1),
          CaptureSessionKind.classicFourShot,
        ),
        isFalse,
      );
    });

    test('one shot satisfies FotoZen', () {
      expect(
        directPtpResultIsUsable(_completed(1), CaptureSessionKind.fotoZen),
        isTrue,
      );
    });

    test('a cancelled result is never usable, even carrying shots', () {
      final cancelled = DirectPtpCaptureResult(
        status: DirectPtpCaptureStatus.cancelled,
        shots: _completed(4).shots,
      );
      expect(
        directPtpResultIsUsable(cancelled, CaptureSessionKind.classicFourShot),
        isFalse,
      );
    });

    test('an error result is never usable', () {
      expect(
        directPtpResultIsUsable(
          const DirectPtpCaptureResult(
            status: DirectPtpCaptureStatus.error,
            errorCode: 'no_device',
          ),
          CaptureSessionKind.fotoZen,
        ),
        isFalse,
      );
    });
  });

  group('review holds', () {
    // FotoZen must never auto-accept: the Flutter screen only schedules
    // auto-accept for Classic multi-shot, so 0 here means "wait for a tap".
    test('FotoZen waits indefinitely for a tap', () {
      expect(directPtpReviewHoldMsFor(CaptureSessionKind.fotoZen), 0);
      expect(directPtpFinalReviewHoldMsFor(CaptureSessionKind.fotoZen), 0);
    });

    test('Classic strip uses the rearrange window mid-strip', () {
      expect(
        directPtpReviewHoldMsFor(CaptureSessionKind.classicFourShot),
        AppConstants.kFlashbackBetweenShotRearrangeDuration.inMilliseconds,
      );
    });

    // Deliberately NOT Flutter's kFlashbackLastShotReviewDuration (2s): the last
    // shot gets the same window as the others so "Retake last" is reachable on
    // the shot most likely to need it. Product decision, not a parity gap — if
    // this ever gets "fixed" back to 2s, that is a regression.
    test('Classic strip gives the final shot the full rearrange window', () {
      final mid = directPtpReviewHoldMsFor(CaptureSessionKind.classicFourShot);
      final last =
          directPtpFinalReviewHoldMsFor(CaptureSessionKind.classicFourShot);
      expect(
        last,
        AppConstants.kFlashbackBetweenShotRearrangeDuration.inMilliseconds,
      );
      expect(last, mid);
    });

    // Regression, caught on hardware 2026-08-20. This was mapped onto
    // flashbackShotReviewHoldDuration's 600ms `total <= 1` branch, so the review
    // blinked past in ~600ms with no chance to retake. That branch is unreachable
    // in Flutter: shouldScheduleFlashbackAutoAccept gates on isFlashbackMultiShot,
    // which is isClassicFourShot **only**, so a Classic 1-shot waits for a tap
    // exactly as FotoZen does.
    test('Classic single 6x4 waits for a tap, like FotoZen', () {
      expect(directPtpReviewHoldMsFor(CaptureSessionKind.classicOneShot), 0);
      expect(
        directPtpFinalReviewHoldMsFor(CaptureSessionKind.classicOneShot),
        0,
      );
    });
  });

  group('countdown headline', () {
    // `showAiIntro` in _buildCountdownOverlay is `!_isClassicPose`, so Classic
    // never shows it. Inferring from shotCount got this wrong: a Classic 1-shot
    // also has shotCount == 1.
    test('FotoZen shows it', () {
      expect(
        directPtpShowCountdownHeadlineFor(CaptureSessionKind.fotoZen),
        isTrue,
      );
    });

    test('neither Classic flow shows it', () {
      expect(
        directPtpShowCountdownHeadlineFor(CaptureSessionKind.classicOneShot),
        isFalse,
      );
      expect(
        directPtpShowCountdownHeadlineFor(CaptureSessionKind.classicFourShot),
        isFalse,
      );
    });
  });
}
