import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/photo_capture/classic_strip_accept_helpers.dart';
import 'package:photobooth/utils/uvc_capture_config.dart';

void main() {
  group('planClassicStripAccept', () {
    test('shot 1 of 4 resumes first and schedules Surprise Me for shot 2 countdown',
        () {
      final plan = planClassicStripAccept(acceptedCountAfterAdd: 1, total: 4);
      expect(plan.resumePreviewBeforeHeavyWork, isTrue);
      expect(plan.scheduleSurpriseMeOnNextCountdown, isTrue);
      expect(plan.finishStrip, isFalse);
    });

    test('shots 2–3 of 4 resume first without Surprise Me', () {
      final mid = planClassicStripAccept(acceptedCountAfterAdd: 2, total: 4);
      expect(mid.resumePreviewBeforeHeavyWork, isTrue);
      expect(mid.scheduleSurpriseMeOnNextCountdown, isFalse);
      expect(mid.finishStrip, isFalse);

      final third = planClassicStripAccept(acceptedCountAfterAdd: 3, total: 4);
      expect(third.resumePreviewBeforeHeavyWork, isTrue);
      expect(third.scheduleSurpriseMeOnNextCountdown, isFalse);
    });

    test('shot 4 finishes strip without remount-first heavy work', () {
      final plan = planClassicStripAccept(acceptedCountAfterAdd: 4, total: 4);
      expect(plan.resumePreviewBeforeHeavyWork, isFalse);
      expect(plan.scheduleSurpriseMeOnNextCountdown, isFalse);
      expect(plan.finishStrip, isTrue);
    });
  });

  test('completePoseReadyGate is idempotent', () {
    final gate = Completer<void>();
    completePoseReadyGate(gate);
    completePoseReadyGate(gate);
    expect(gate.isCompleted, isTrue);
  });

  test('shouldKeepUvcControllerOpen for Classic 4-shot', () {
    expect(
      UvcCaptureConfig.shouldKeepUvcControllerOpen(
        classicFourShotSession: false,
      ),
      isFalse,
    );
    expect(
      UvcCaptureConfig.shouldKeepUvcControllerOpen(
        classicFourShotSession: true,
      ),
      isTrue,
    );
    expect(UvcCaptureConfig.keepControllerOpenDuringReview, isFalse);
    expect(UvcCaptureConfig.keepControllerOpenForClassicFourShot, isTrue);
  });
}
