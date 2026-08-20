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

  test('androidStreamFallbackCaptureEligible is true for external, TV, tablet',
      () {
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
        deviceType: AppDeviceType.androidTablet,
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

  test('takePictureTimeoutForDevice is shorter on Android TV kiosks', () {
    expect(
      takePictureTimeoutForDevice(
        camera: back,
        deviceType: AppDeviceType.androidTv,
      ),
      const Duration(seconds: 4),
    );
    expect(
      takePictureTimeoutForDevice(
        camera: external,
        deviceType: AppDeviceType.androidPhone,
      ),
      const Duration(seconds: 6),
    );
    expect(
      takePictureTimeoutForDevice(
        camera: back,
        deviceType: AppDeviceType.androidTablet,
      ),
      const Duration(seconds: 4),
    );
    expect(
      takePictureTimeoutForDevice(
        camera: back,
        deviceType: AppDeviceType.androidPhone,
      ),
      const Duration(seconds: 12),
    );
  });

  test('preferImmediateStreamFallbackAfterStillFailure for TV and tablet', () {
    expect(
      preferImmediateStreamFallbackAfterStillFailure(
        camera: external,
        deviceType: AppDeviceType.androidTv,
      ),
      isTrue,
    );
    expect(
      preferImmediateStreamFallbackAfterStillFailure(
        camera: back,
        deviceType: AppDeviceType.androidTablet,
      ),
      isTrue,
    );
    expect(
      preferImmediateStreamFallbackAfterStillFailure(
        camera: external,
        deviceType: AppDeviceType.androidTablet,
      ),
      isFalse,
    );
    expect(
      preferImmediateStreamFallbackAfterStillFailure(
        camera: external,
        deviceType: AppDeviceType.androidPhone,
      ),
      isFalse,
    );
    expect(
      preferImmediateStreamFallbackAfterStillFailure(
        camera: back,
        deviceType: AppDeviceType.androidPhone,
      ),
      isFalse,
    );
  });

  test('looksLikeCameraXRecoverableError matches plugin copy', () {
    expect(
      looksLikeCameraXRecoverableError(
        'The camera device has encountered a recoverable error. '
        'CameraX will attempt to recover from the error.',
      ),
      isTrue,
    );
    expect(looksLikeCameraXRecoverableError('Camera permission denied'), isFalse);
  });

  test('shouldSurfaceCameraControllerErrorAsFatal hides recoverable noise', () {
    expect(
      shouldSurfaceCameraControllerErrorAsFatal(
        'The camera device has encountered a recoverable error. '
        'CameraX will attempt to recover from the error.',
      ),
      isFalse,
    );
    expect(
      shouldSurfaceCameraControllerErrorAsFatal('Failed to open camera'),
      isTrue,
    );
    expect(shouldSurfaceCameraControllerErrorAsFatal(null), isTrue);
  });

  test('isRecoverableTakePictureError covers CameraX and closed-device cases', () {
    expect(
      isRecoverableTakePictureError('otherrecoverableerror'.toLowerCase()),
      isTrue,
    );
    expect(isRecoverableTakePictureError('camera is closed'), isTrue);
    expect(isRecoverableTakePictureError('permission denied'), isFalse);
  });
}
