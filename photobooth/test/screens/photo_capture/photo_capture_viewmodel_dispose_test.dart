import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/photo_capture/photo_capture_viewmodel.dart';

void main() {
  test('CaptureViewModel notifyListeners is safe after dispose', () {
    final vm = CaptureViewModel();
    vm.dispose();
    expect(vm.isDisposed, isTrue);
    expect(() => vm.notifyListeners(), returnsNormally);
  });

  test('markAwaitingCameraRemount shows loading before enumeration', () {
    final vm = CaptureViewModel();
    expect(vm.isLoadingCameras, isFalse);
    vm.markAwaitingCameraRemount();
    expect(vm.isLoadingCameras, isTrue);
    vm.markAwaitingCameraRemount();
    expect(vm.isLoadingCameras, isTrue);
    vm.dispose();
  });
}
