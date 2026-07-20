import 'package:photobooth/screens/photo_capture/photo_capture_idle_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CaptureScreenIdleInput', () {
    test('stores constructor fields', () {
      const input = CaptureScreenIdleInput(
        isNavigatingAway: false,
        isCapturing: false,
        isUploading: false,
        isCountingDown: false,
        appInForeground: true,
        isWaitingForPhoneUpload: true,
      );
      expect(input.isCapturing, isFalse);
      expect(input.appInForeground, isTrue);
      expect(input.isWaitingForPhoneUpload, isTrue);
    });
  });

  group('captureScreenIdleTimerShouldRun', () {
    const active = CaptureScreenIdleInput(
      isNavigatingAway: false,
      isCapturing: false,
      isUploading: false,
      isCountingDown: false,
      appInForeground: true,
    );

    test('runs on idle live feed', () {
      expect(captureScreenIdleTimerShouldRun(active), isTrue);
    });

    test('stops while navigating away', () {
      expect(
        captureScreenIdleTimerShouldRun(
          const CaptureScreenIdleInput(
            isNavigatingAway: true,
            isCapturing: false,
            isUploading: false,
            isCountingDown: false,
            appInForeground: true,
          ),
        ),
        isFalse,
      );
    });

    test('stops while app is backgrounded', () {
      expect(
        captureScreenIdleTimerShouldRun(
          const CaptureScreenIdleInput(
            isNavigatingAway: false,
            isCapturing: false,
            isUploading: false,
            isCountingDown: false,
            appInForeground: false,
          ),
        ),
        isFalse,
      );
    });

    test('stops during capture, upload, or countdown', () {
      expect(
        captureScreenIdleTimerShouldRun(
          const CaptureScreenIdleInput(
            isNavigatingAway: false,
            isCapturing: true,
            isUploading: false,
            isCountingDown: false,
            appInForeground: true,
          ),
        ),
        isFalse,
      );
      expect(
        captureScreenIdleTimerShouldRun(
          const CaptureScreenIdleInput(
            isNavigatingAway: false,
            isCapturing: false,
            isUploading: true,
            isCountingDown: false,
            appInForeground: true,
          ),
        ),
        isFalse,
      );
      expect(
        captureScreenIdleTimerShouldRun(
          const CaptureScreenIdleInput(
            isNavigatingAway: false,
            isCapturing: false,
            isUploading: false,
            isCountingDown: true,
            appInForeground: true,
          ),
        ),
        isFalse,
      );
    });

    test('stops while waiting for phone QR upload', () {
      expect(
        captureScreenIdleTimerShouldRun(
          const CaptureScreenIdleInput(
            isNavigatingAway: false,
            isCapturing: false,
            isUploading: false,
            isCountingDown: false,
            appInForeground: true,
            isWaitingForPhoneUpload: true,
          ),
        ),
        isFalse,
      );
    });
  });
}
