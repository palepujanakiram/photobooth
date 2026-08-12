import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/utils/classic_one_shot_fsm.dart';

void main() {
  group('classicOneShotMayStartCountdown', () {
    test('only idle and needsGuest', () {
      expect(classicOneShotMayStartCountdown(ClassicOneShotPhase.idle), isTrue);
      expect(
        classicOneShotMayStartCountdown(ClassicOneShotPhase.needsGuest),
        isTrue,
      );
      for (final phase in ClassicOneShotPhase.values) {
        if (phase == ClassicOneShotPhase.idle ||
            phase == ClassicOneShotPhase.needsGuest) {
          continue;
        }
        expect(
          classicOneShotMayStartCountdown(phase),
          isFalse,
          reason: '$phase must not start another countdown',
        );
      }
    });
  });

  group('classicOneShotBlocksAutoAdvance', () {
    test('idle alone allows auto cameraReady', () {
      expect(classicOneShotBlocksAutoAdvance(ClassicOneShotPhase.idle), isFalse);
      expect(
        classicOneShotBlocksAutoAdvance(ClassicOneShotPhase.needsGuest),
        isTrue,
      );
      expect(
        classicOneShotBlocksAutoAdvance(ClassicOneShotPhase.counting),
        isTrue,
      );
    });
  });

  group('classicOneShotTransition', () {
    test('cameraReady starts countdown once from idle only', () {
      expect(
        classicOneShotTransition(
          phase: ClassicOneShotPhase.idle,
          event: ClassicOneShotEvent.cameraReady,
        ),
        ClassicOneShotPhase.counting,
      );
      expect(
        classicOneShotTransition(
          phase: ClassicOneShotPhase.needsGuest,
          event: ClassicOneShotEvent.cameraReady,
        ),
        isNull,
      );
      expect(
        classicOneShotTransition(
          phase: ClassicOneShotPhase.counting,
          event: ClassicOneShotEvent.cameraReady,
        ),
        isNull,
      );
    });

    test('failed capture never returns to idle (no auto-loop)', () {
      expect(
        classicOneShotTransition(
          phase: ClassicOneShotPhase.counting,
          event: ClassicOneShotEvent.captureFailed,
        ),
        ClassicOneShotPhase.needsGuest,
      );
      expect(
        classicOneShotTransition(
          phase: ClassicOneShotPhase.capturing,
          event: ClassicOneShotEvent.captureFailed,
        ),
        ClassicOneShotPhase.needsGuest,
      );
      expect(
        classicOneShotTransition(
          phase: ClassicOneShotPhase.finishing,
          event: ClassicOneShotEvent.captureFailed,
        ),
        ClassicOneShotPhase.needsGuest,
      );
      expect(
        classicOneShotTransition(
          phase: ClassicOneShotPhase.needsGuest,
          event: ClassicOneShotEvent.cameraReady,
        ),
        isNull,
      );
    });

    test('success path is linear to done', () {
      var phase = ClassicOneShotPhase.idle;
      phase = classicOneShotTransition(
        phase: phase,
        event: ClassicOneShotEvent.cameraReady,
      )!;
      expect(phase, ClassicOneShotPhase.counting);
      phase = classicOneShotTransition(
        phase: phase,
        event: ClassicOneShotEvent.shutterStarted,
      )!;
      expect(phase, ClassicOneShotPhase.capturing);
      phase = classicOneShotTransition(
        phase: phase,
        event: ClassicOneShotEvent.stillReady,
      )!;
      expect(phase, ClassicOneShotPhase.captured);
      phase = classicOneShotTransition(
        phase: phase,
        event: ClassicOneShotEvent.finishStarted,
      )!;
      expect(phase, ClassicOneShotPhase.finishing);
      phase = classicOneShotTransition(
        phase: phase,
        event: ClassicOneShotEvent.finished,
      )!;
      expect(phase, ClassicOneShotPhase.done);
      expect(
        classicOneShotTransition(
          phase: phase,
          event: ClassicOneShotEvent.cameraReady,
        ),
        isNull,
      );
      expect(
        classicOneShotTransition(
          phase: phase,
          event: ClassicOneShotEvent.guestCapture,
        ),
        isNull,
      );
    });

    test('external shutter only from idle (not needsGuest retries)', () {
      expect(
        classicOneShotMayAcceptExternalShutter(ClassicOneShotPhase.idle),
        isTrue,
      );
      expect(
        classicOneShotMayAcceptExternalShutter(ClassicOneShotPhase.needsGuest),
        isFalse,
      );
      expect(
        classicOneShotMayAcceptExternalShutter(ClassicOneShotPhase.counting),
        isFalse,
      );
      expect(
        classicOneShotMayAcceptExternalShutter(ClassicOneShotPhase.capturing),
        isFalse,
      );
      expect(
        classicOneShotMayAcceptExternalShutter(ClassicOneShotPhase.captured),
        isFalse,
      );
    });

    test('guest retake returns to needsGuest only', () {
      expect(
        classicOneShotTransition(
          phase: ClassicOneShotPhase.captured,
          event: ClassicOneShotEvent.guestRetake,
        ),
        ClassicOneShotPhase.needsGuest,
      );
      expect(
        classicOneShotTransition(
          phase: ClassicOneShotPhase.idle,
          event: ClassicOneShotEvent.guestRetake,
        ),
        isNull,
      );
    });

    test('finished accepts captured without finishStarted', () {
      expect(
        classicOneShotTransition(
          phase: ClassicOneShotPhase.captured,
          event: ClassicOneShotEvent.finished,
        ),
        ClassicOneShotPhase.done,
      );
    });
  });
}
