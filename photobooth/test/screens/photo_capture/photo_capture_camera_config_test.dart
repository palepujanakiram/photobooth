import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/photo_capture/photo_capture_camera_config.dart';
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

  test('isExternalCaptureCamera detects external lens and name', () {
    expect(
      isExternalCaptureCamera(external, (n) => n.contains('USB')),
      isTrue,
    );
    expect(
      isExternalCaptureCamera(back, (n) => n.contains('USB')),
      isFalse,
    );
    expect(
      isExternalCaptureCamera(
        const CameraDescription(
          name: 'HDMI Capture',
          lensDirection: CameraLensDirection.back,
          sensorOrientation: 0,
        ),
        (n) => n.toLowerCase().contains('hdmi'),
      ),
      isTrue,
    );
  });

  test('captureResolutionPreset uses high for external including on TV', () {
    expect(
      captureResolutionPreset(
        deviceType: AppDeviceType.androidTv,
        isExternal: true,
      ),
      ResolutionPreset.high,
    );
    expect(
      captureResolutionPreset(
        deviceType: AppDeviceType.androidTv,
        isExternal: false,
      ),
      ResolutionPreset.low,
    );
    expect(
      captureResolutionPreset(
        deviceType: AppDeviceType.androidPhone,
        isExternal: true,
      ),
      ResolutionPreset.high,
    );
    expect(
      captureResolutionPreset(
        deviceType: AppDeviceType.androidPhone,
        isExternal: false,
      ),
      ResolutionPreset.high,
    );
  });

  test('captureStreamFormat returns yuv on Android TV / external', () {
    expect(
      captureStreamFormat(
        deviceType: AppDeviceType.androidTv,
        isExternal: false,
      ),
      ImageFormatGroup.yuv420,
    );
    expect(
      captureStreamFormat(
        deviceType: AppDeviceType.androidPhone,
        isExternal: true,
      ),
      ImageFormatGroup.yuv420,
    );
    expect(
      captureStreamFormat(
        deviceType: AppDeviceType.iosPhone,
        isExternal: false,
      ),
      ImageFormatGroup.jpeg,
    );
  });
}
