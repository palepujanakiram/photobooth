import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
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

  test('captureResolutionPreset prefers high for non-TV external webcams', () {
    expect(
      captureResolutionPreset(
        deviceType: AppDeviceType.androidTv,
        isExternal: true,
      ),
      ResolutionPreset.medium,
    );
    expect(
      captureResolutionPreset(
        deviceType: AppDeviceType.androidTv,
        isExternal: false,
      ),
      ResolutionPreset.medium,
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
        deviceType: AppDeviceType.androidTablet,
        isExternal: true,
        preferPrintQuality: true,
      ),
      ResolutionPreset.veryHigh,
    );
    expect(
      captureResolutionPreset(
        deviceType: AppDeviceType.androidPhone,
        isExternal: false,
      ),
      ResolutionPreset.veryHigh,
    );
    expect(
      captureResolutionPreset(
        deviceType: AppDeviceType.androidTablet,
        isExternal: false,
        preferPrintQuality: true,
      ),
      ResolutionPreset.high,
    );
    expect(
      captureResolutionPreset(
        deviceType: AppDeviceType.androidPhone,
        isExternal: false,
        preferPrintQuality: true,
      ),
      ResolutionPreset.max,
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
        deviceType: AppDeviceType.androidTablet,
        isExternal: false,
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

  test('canPrewarmLiveCameraOnPlatform allows Android and iOS only', () {
    expect(
      canPrewarmLiveCameraOnPlatform(
        isWeb: false,
        platform: TargetPlatform.android,
      ),
      isTrue,
    );
    expect(
      canPrewarmLiveCameraOnPlatform(
        isWeb: false,
        platform: TargetPlatform.iOS,
      ),
      isTrue,
    );
    expect(
      canPrewarmLiveCameraOnPlatform(
        isWeb: true,
        platform: TargetPlatform.iOS,
      ),
      isFalse,
    );
    expect(
      canPrewarmLiveCameraOnPlatform(
        isWeb: false,
        platform: TargetPlatform.windows,
      ),
      isFalse,
    );
  });

  test('shouldUseFastCameraDescriptionSwitch is off on iOS', () {
    expect(shouldUseFastCameraDescriptionSwitch(TargetPlatform.iOS), isFalse);
    expect(
      shouldUseFastCameraDescriptionSwitch(TargetPlatform.android),
      isTrue,
    );
  });
}
