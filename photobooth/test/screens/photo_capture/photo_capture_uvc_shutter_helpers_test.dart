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

  test('isUvcShutterCaptureEvent ignores non-shutter buttons', () {
    expect(
      isUvcShutterCaptureEvent(button: 2, state: 1),
      isFalse,
    );
  });

  test('shouldTriggerUvcShutterCapture debounces rapid events', () {
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
  });
}
