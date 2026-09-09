import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/photo_capture/direct_ptp_capture_helpers.dart';
import 'package:photobooth/services/event_pipeline/capture/direct_ptp_capture_source.dart';
import 'package:photobooth/utils/capture_session_kind.dart';
import 'package:photobooth/utils/classic_pose_countdown.dart';

/// The native capture screen is shared between the guest kiosk and the event
/// pipeline, so every change made for the event has to be provably invisible to
/// the kiosk. Both of them are gated the same way, on `countdownSeconds == 0`:
///
/// - the retake-returns-to-live-view branch in `CanonCaptureActivity`
/// - nothing else; the event colours are null for a kiosk request
///
/// So the guarantee reduces to one fact: **no kiosk path can produce a
/// countdown of zero.** These tests pin that.
void main() {
  group('the event session is the only one with no countdown', () {
    test('the event capture request has no countdown', () {
      final args = DirectPtpCaptureSource.requestFor().toArguments();
      expect(args['countdownSeconds'], 0);
    });

    test('every kiosk session kind keeps a countdown', () {
      for (final kind in CaptureSessionKind.values) {
        expect(
          directPtpCountdownSecondsFor(kind),
          greaterThan(0),
          reason: '$kind would take the event-only retake path',
        );
      }
    });

    test('a misconfigured Classic countdown still cannot reach zero', () {
      // The admin range is clamped, so even a bad backend value has a floor.
      for (final raw in <int?>[null, -10, 0, 1, 4, 5, 15, 999]) {
        expect(
          normalizeClassicPoseCountdownSeconds(raw),
          greaterThan(0),
          reason: 'raw=$raw',
        );
      }
    });
  });

  group('event chrome never leaks into a kiosk session', () {
    test('the colours are absent unless the event supplies them', () {
      // A kiosk request never sets these, so applyEventChrome leaves every
      // view exactly as the layout declared it.
      final args = DirectPtpCaptureSource.requestFor().toArguments();
      expect(args['inkColor'], isNull);
      expect(args['accentColor'], isNull);
      expect(args['backgroundColor'], isNull);
    });
  });
}
