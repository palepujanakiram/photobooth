import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/photo_capture/photo_capture_camera_selection_helpers.dart';
import 'package:photobooth/utils/app_device_type.dart';
import 'package:photobooth/utils/app_strings.dart';

void main() {
  const external = CameraDescription(
    name: 'USB Webcam',
    lensDirection: CameraLensDirection.external,
    sensorOrientation: 0,
  );
  const front = CameraDescription(
    name: 'Front',
    lensDirection: CameraLensDirection.front,
    sensorOrientation: 270,
  );
  const back = CameraDescription(
    name: 'Back',
    lensDirection: CameraLensDirection.back,
    sensorOrientation: 90,
  );

  test('camerasIncludeExternal detects external lens and usb name', () {
    expect(camerasIncludeExternal([external]), isTrue);
    expect(camerasIncludeExternal([front]), isFalse);
    expect(
      camerasIncludeExternal([
        const CameraDescription(
          name: 'HDMI Capture',
          lensDirection: CameraLensDirection.back,
          sensorOrientation: 0,
        ),
      ]),
      isFalse,
    );
  });

  test('cameraPickerUsbHint on tablet with only built-in cameras', () {
    expect(
      cameraPickerUsbHint(
        deviceType: AppDeviceType.androidTablet,
        cameras: [front],
      ),
      AppStrings.cameraPickerBuiltInOnlyHint,
    );
    expect(
      cameraPickerUsbHint(
        deviceType: AppDeviceType.androidTv,
        cameras: [front, back],
      ),
      AppStrings.cameraPickerBuiltInOnlyHint,
    );
  });

  test('cameraPickerUsbHint hidden when external present or not tablet', () {
    expect(
      cameraPickerUsbHint(
        deviceType: AppDeviceType.androidTablet,
        cameras: [front, external],
      ),
      isNull,
    );
    expect(
      cameraPickerUsbHint(
        deviceType: AppDeviceType.androidPhone,
        cameras: [front],
      ),
      isNull,
    );
    expect(
      cameraPickerUsbHint(
        deviceType: AppDeviceType.androidTablet,
        cameras: [],
      ),
      isNull,
    );
  });

  test('camerasForDeviceType keeps external only on Android TV', () {
    const external = CameraDescription(
      name: 'USB Webcam',
      lensDirection: CameraLensDirection.external,
      sensorOrientation: 0,
    );
    const front = CameraDescription(
      name: 'Front',
      lensDirection: CameraLensDirection.front,
      sensorOrientation: 270,
    );
    expect(
      camerasForDeviceType(
        cameras: [front, external],
        deviceType: AppDeviceType.androidTv,
        looksLikeExternalName: (_) => false,
      ),
      [external],
    );
    expect(
      camerasForDeviceType(
        cameras: [front, external],
        deviceType: AppDeviceType.androidPhone,
        looksLikeExternalName: (_) => false,
      ),
      [front],
    );
  });

  test('uniqueCamerasByDisplayName keeps one entry per display name', () {
    const dupFront = CameraDescription(
      name: 'Front-alt',
      lensDirection: CameraLensDirection.front,
      sensorOrientation: 270,
    );
    final unique = uniqueCamerasByDisplayName(
      [front, dupFront, back],
      (c) => c.lensDirection == CameraLensDirection.front ? 'Front Camera' : 'Back Camera',
    );
    expect(unique, hasLength(2));
    expect(unique.map((c) => c.name), ['Front', 'Back']);
  });
}
