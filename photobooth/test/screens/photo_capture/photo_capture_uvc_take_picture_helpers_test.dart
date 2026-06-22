import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/photo_capture/photo_capture_uvc_take_picture_helpers.dart';

void main() {
  test('isUvcShutterCaptureSource includes preview interrupt and UVC button', () {
    expect(isUvcShutterCaptureSource('preview_interrupt'), isTrue);
    expect(isUvcShutterCaptureSource('uvc_button'), isTrue);
    expect(isUvcShutterCaptureSource('android_key_27'), isTrue);
    expect(isUvcShutterCaptureSource('ui_button'), isFalse);
  });

  test('uvcAllowsRasterFallback only for preview interrupt', () {
    expect(uvcAllowsRasterFallback('preview_interrupt'), isTrue);
    expect(uvcAllowsRasterFallback('ui_button'), isFalse);
  });

  test('uvcTakePictureAttemptsForSource always uses single attempt', () {
    expect(uvcTakePictureAttemptsForSource('preview_interrupt'), 1);
    expect(uvcTakePictureAttemptsForSource('ui_button'), 1);
    expect(uvcTakePictureAttemptsForSource('uvc_button'), 1);
  });
}
