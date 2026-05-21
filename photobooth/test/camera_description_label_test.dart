import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/photo_capture/camera_description_label.dart';
import 'package:photobooth/utils/app_strings.dart';

void main() {
  test('looksLikeExternalCameraName detects usb in name', () {
    expect(looksLikeExternalCameraName('USB Webcam HD'), isTrue);
  });

  test('looksLikeExternalCameraName rejects built-in', () {
    expect(looksLikeExternalCameraName('built-in_wide'), isFalse);
  });

  test('cameraDescriptionLabel marks external lens', () {
    const cam = CameraDescription(
      name: 'USB Webcam',
      lensDirection: CameraLensDirection.external,
      sensorOrientation: 0,
    );
    expect(
      cameraDescriptionLabel(cam),
      contains(AppStrings.cameraLabelExternal),
    );
  });
}
