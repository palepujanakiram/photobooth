import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/photo_capture/photo_capture_camera_config.dart';
import 'package:photobooth/screens/photo_capture/photo_capture_viewmodel_helpers.dart';
import 'package:photobooth/utils/app_device_type.dart';

void main() {
  const external = CameraDescription(
    name: 'USB Camera',
    lensDirection: CameraLensDirection.external,
    sensorOrientation: 0,
  );
  const back = CameraDescription(
    name: 'Back',
    lensDirection: CameraLensDirection.back,
    sensorOrientation: 90,
  );

  test('androidStreamFallbackCaptureEligible is true for external and Android TV', () {
    expect(
      androidStreamFallbackCaptureEligible(
        camera: external,
        deviceType: AppDeviceType.androidPhone,
      ),
      isTrue,
    );
    expect(
      androidStreamFallbackCaptureEligible(
        camera: back,
        deviceType: AppDeviceType.androidTv,
      ),
      isTrue,
    );
    expect(
      androidStreamFallbackCaptureEligible(
        camera: back,
        deviceType: AppDeviceType.androidPhone,
      ),
      isFalse,
    );
  });

  test('isExternalCaptureCamera detects HDMI/USB names', () {
    expect(
      isExternalCaptureCamera(
        const CameraDescription(
          name: 'HDMI Capture',
          lensDirection: CameraLensDirection.back,
          sensorOrientation: 0,
        ),
        (name) => name.toLowerCase().contains('hdmi'),
      ),
      isTrue,
    );
  });
}
