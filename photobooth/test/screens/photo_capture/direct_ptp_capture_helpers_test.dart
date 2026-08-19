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

    test('Classic strip shortens the hold on the final shot', () {
      final mid = directPtpReviewHoldMsFor(CaptureSessionKind.classicFourShot);
      final last =
          directPtpFinalReviewHoldMsFor(CaptureSessionKind.classicFourShot);
      expect(
        last,
        AppConstants.kFlashbackLastShotReviewDuration.inMilliseconds,
      );
      // The point of the final hold: hand off to looks quickly rather than
      // making the guest wait out a rearrange window with nothing to rearrange.
      expect(last, lessThan(mid));
    });

    test('Classic single 6x4 only flashes the still', () {
      expect(
        directPtpReviewHoldMsFor(CaptureSessionKind.classicOneShot),
        AppConstants.kFlashbackSingleShotReviewMs,
      );
      expect(
        directPtpFinalReviewHoldMsFor(CaptureSessionKind.classicOneShot),
        AppConstants.kFlashbackSingleShotReviewMs,
      );
    });
  });
}
