import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/photo_capture/photo_capture_uvc_shutter_helpers.dart';

void main() {
  test('isUvcShutterCaptureEvent accepts shutter press', () {
    expect(
      isUvcShutterCaptureEvent(button: 1, state: 1),
      isTrue,
    );
  });

  test('isUvcShutterCaptureEvent accepts shutter release when enabled', () {
    expect(
      isUvcShutterCaptureEvent(button: 1, state: 0),
      isTrue,
    );
    expect(
      isUvcShutterCaptureEvent(button: 1, state: 0, acceptRelease: false),
      isFalse,
    );
  });

  test('isUvcShutterCaptureEvent accepts alternate button ids', () {
    expect(isUvcShutterCaptureEvent(button: 2, state: 1), isTrue);
    expect(isUvcShutterCaptureEvent(button: 0, state: 2), isTrue);
  });

  test('isUvcShutterCaptureEvent ignores invalid button id', () {
    expect(isUvcShutterCaptureEvent(button: -1, state: 1), isFalse);
  });

  test('shouldTriggerUvcShutterFromInterrupt debounces like button events', () {
    final t0 = DateTime(2026, 6, 17, 12);
    expect(
      shouldTriggerUvcShutterCapture(
        button: 1,
        state: 1,
        lastCaptureAt: null,
        now: t0,
      ),
      isTrue,
    );
    expect(
      shouldTriggerUvcShutterCapture(
        button: 1,
        state: 0,
        lastCaptureAt: t0,
        now: t0.add(const Duration(milliseconds: 100)),
      ),
      isFalse,
    );
    expect(
      shouldTriggerUvcShutterCapture(
        button: 1,
        state: 1,
        lastCaptureAt: t0,
        now: t0.add(kUvcShutterDebounce),
      ),
      isTrue,
    );
    expect(
      shouldTriggerUvcShutterFromInterrupt(
        lastCaptureAt: t0,
        now: t0.add(const Duration(milliseconds: 100)),
      ),
      isFalse,
    );
  });

  test('isWithinUvcShutterGrace is true before grace expires', () {
    final now = DateTime(2026, 6, 17, 12);
    final until = now.add(const Duration(seconds: 4));
    expect(
      isWithinUvcShutterGrace(graceUntil: until, now: now),
      isTrue,
    );
    expect(
      isWithinUvcShutterGrace(
        graceUntil: until,
        now: now.add(const Duration(seconds: 5)),
      ),
      isFalse,
    );
  });

  test('shouldIgnoreUvcPreviewInterrupt filters connect churn only during warmup', () {
    expect(
      shouldIgnoreUvcPreviewInterrupt(
        holdLiveFeedClosed: false,
        previewWarmupActive: true,
        reason: 'The surface was destroyed',
        phaseIsLive: true,
      ),
      isTrue,
    );
    expect(
      shouldIgnoreUvcPreviewInterrupt(
        holdLiveFeedClosed: false,
        previewWarmupActive: false,
        reason: 'The surface was destroyed',
        phaseIsLive: true,
      ),
      isFalse,
    );
    expect(
      shouldIgnoreUvcPreviewInterrupt(
        holdLiveFeedClosed: true,
        previewWarmupActive: false,
        reason: 'The surface was destroyed',
        phaseIsLive: true,
      ),
      isTrue,
    );
  });
}
