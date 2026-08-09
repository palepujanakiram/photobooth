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
}
