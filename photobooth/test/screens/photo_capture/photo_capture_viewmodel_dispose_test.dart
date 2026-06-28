import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/photo_capture/photo_capture_viewmodel.dart';

void main() {
  test('CaptureViewModel notifyListeners is safe after dispose', () {
    final vm = CaptureViewModel();
    vm.dispose();
    expect(vm.isDisposed, isTrue);
    expect(() => vm.notifyListeners(), returnsNormally);
  });
}
