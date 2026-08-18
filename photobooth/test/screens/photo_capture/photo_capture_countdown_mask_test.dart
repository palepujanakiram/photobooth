import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/photo_capture/photo_capture_viewmodel.dart';

void main() {
  test(
    'captureWithCountdown still runs shutter after onCountdownFinished '
    'makes canStart false (HDMI mask arm)',
    () async {
      final vm = CaptureViewModel();
      var maskArmed = false;
      var shutterRan = false;

      await vm.captureWithCountdown(
        () async {
          shutterRan = true;
        },
        canStart: () => !maskArmed,
        countdownSeconds: 1,
        onCountdownFinished: () {
          maskArmed = true;
        },
      );

      expect(maskArmed, isTrue);
      expect(shutterRan, isTrue);
      vm.dispose();
    },
  );

  test('captureWithCountdown holds the last tick for a full second', () async {
    final vm = CaptureViewModel();
    final started = DateTime.now();
    await vm.captureWithCountdown(
      () async {},
      canStart: () => true,
      countdownSeconds: 1,
    );
    expect(
      DateTime.now().difference(started) >= const Duration(milliseconds: 900),
      isTrue,
    );
    vm.dispose();
  });

  test('captureWithCountdown invokes onCountdownStep each second', () async {
    final vm = CaptureViewModel();
    final steps = <int>[];
    await vm.captureWithCountdown(
      () async {},
      canStart: () => true,
      countdownSeconds: 3,
      onCountdownStep: steps.add,
    );
    expect(steps, [3, 2, 1]);
    vm.dispose();
  });

  test('captureWithCountdown skips remaining ticks when captureNow is true',
      () async {
    final vm = CaptureViewModel();
    var shutterRan = false;
    final started = DateTime.now();
    await vm.captureWithCountdown(
      () async {
        shutterRan = true;
      },
      canStart: () => true,
      countdownSeconds: 8,
      captureNow: () async => true,
    );
    expect(shutterRan, isTrue);
    expect(
      DateTime.now().difference(started) < const Duration(seconds: 2),
      isTrue,
    );
    vm.dispose();
  });
}
