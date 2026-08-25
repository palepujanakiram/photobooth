import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/photo_capture/photo_capture_camera_selection_helpers.dart';
import 'package:photobooth/screens/photo_capture/photo_capture_viewmodel.dart';
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
      isTrue,
    );
    expect(camerasIncludeExternal([back]), isFalse);
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

  test('camerasForDeviceType lists all cameras with external first', () {
    expect(
      camerasForDeviceType(
        cameras: [front, external],
        deviceType: AppDeviceType.androidTv,
        looksLikeExternalName: (_) => false,
      ),
      [external, front],
    );
    expect(
      camerasForDeviceType(
        cameras: [front, external],
        deviceType: AppDeviceType.androidPhone,
        looksLikeExternalName: (_) => false,
      ),
      [external, front],
    );
  });

  test('captureCamerasForDevice lists all cameras on Android TV', () {
    expect(
      captureCamerasForDevice(
        cameras: [front, external],
        deviceType: AppDeviceType.androidTv,
        looksLikeExternalName: (_) => false,
      ),
      [external, front],
    );
    expect(
      captureCamerasForDevice(
        cameras: [front, back],
        deviceType: AppDeviceType.androidTv,
        looksLikeExternalName: (_) => false,
      ),
      [front, back],
    );
  });

  test('pickPreferredCaptureCamera chooses external when present', () {
    expect(
      pickPreferredCaptureCamera(
        cameras: [front, external],
        deviceType: AppDeviceType.androidTv,
        looksLikeExternalName: (_) => false,
      ),
      external,
    );
    expect(
      pickPreferredCaptureCamera(
        cameras: [front, external],
        deviceType: AppDeviceType.iosPhone,
        looksLikeExternalName: (_) => false,
      ),
      external,
    );
    expect(
      pickPreferredCaptureCamera(
        cameras: [back, front],
        deviceType: AppDeviceType.androidPhone,
        looksLikeExternalName: (_) => false,
      ),
      front,
    );
    expect(
      pickPreferredCaptureCamera(
        cameras: [front],
        deviceType: AppDeviceType.androidTv,
        looksLikeExternalName: (_) => false,
      ),
      front,
    );
    expect(
      pickPreferredCaptureCamera(
        cameras: [back],
        deviceType: AppDeviceType.iosPhone,
        looksLikeExternalName: (_) => false,
      ),
      back,
    );
    expect(
      () => pickPreferredCaptureCamera(
        cameras: const [],
        deviceType: AppDeviceType.androidPhone,
        looksLikeExternalName: (_) => false,
      ),
      throwsStateError,
    );
  });

  test('captureCamerasForDevice keeps external and built-in on phones', () {
    expect(
      captureCamerasForDevice(
        cameras: [front, external],
        deviceType: AppDeviceType.androidPhone,
        looksLikeExternalName: (_) => false,
      ),
      [external, front],
    );
    expect(
      captureCamerasForDevice(
        cameras: [front, external],
        deviceType: AppDeviceType.iosPhone,
        looksLikeExternalName: (_) => false,
      ),
      [external, front],
    );
  });

  test('captureCamerasForDevice falls back to built-in on iPad', () {
    expect(
      captureCamerasForDevice(
        cameras: [front, back],
        deviceType: AppDeviceType.iosTablet,
        looksLikeExternalName: (_) => false,
      ),
      [front, back],
    );
  });

  test('captureCamerasForDevice empty list and non-kiosk fallback', () {
    expect(
      captureCamerasForDevice(
        cameras: const [],
        deviceType: AppDeviceType.androidTv,
        looksLikeExternalName: (_) => false,
      ),
      isEmpty,
    );
    expect(
      captureCamerasForDevice(
        cameras: [front, back],
        deviceType: null,
        looksLikeExternalName: (_) => false,
      ),
      [front, back],
    );
    expect(
      captureCamerasForDevice(
        cameras: [back, front],
        deviceType: AppDeviceType.unknown,
        looksLikeExternalName: (_) => false,
      ),
      [front, back],
    );
  });

  test('captureCamerasForDevice uses name heuristic on tablet', () {
    const hdmi = CameraDescription(
      name: 'HDMI Capture Card',
      lensDirection: CameraLensDirection.back,
      sensorOrientation: 0,
    );
    expect(
      captureCamerasForDevice(
        cameras: [front, hdmi],
        deviceType: AppDeviceType.androidTablet,
        looksLikeExternalName: (name) => name.contains('HDMI'),
      ),
      [hdmi, front],
    );
    expect(
      pickPreferredCaptureCamera(
        cameras: [front, hdmi],
        deviceType: AppDeviceType.androidTablet,
        looksLikeExternalName: (name) => name.contains('HDMI'),
      ),
      hdmi,
    );
  });

  test('camerasForDeviceType null and unknown keep all cameras', () {
    expect(
      camerasForDeviceType(
        cameras: [front, external],
        deviceType: null,
        looksLikeExternalName: (_) => false,
      ),
      [external, front],
    );
    expect(
      camerasForDeviceType(
        cameras: [front, external],
        deviceType: AppDeviceType.unknown,
        looksLikeExternalName: (_) => false,
      ),
      [external, front],
    );
  });

  test('kioskHasCachedExternalCamera rejects missing cache', () {
    expect(
      kioskHasCachedExternalCamera(
        cached: null,
        deviceType: AppDeviceType.androidTv,
        looksLikeExternalName: (_) => false,
      ),
      isFalse,
    );
    expect(
      kioskHasCachedExternalCamera(
        cached: const [],
        deviceType: AppDeviceType.androidTv,
        looksLikeExternalName: (_) => false,
      ),
      isFalse,
    );
    expect(
      kioskHasCachedExternalCamera(
        cached: [external],
        deviceType: null,
        looksLikeExternalName: (_) => false,
      ),
      isFalse,
    );
  });

  test('orderCaptureCamerasExternalFirst prefers external then front', () {
    expect(
      orderCaptureCamerasExternalFirst(
        cameras: [front, external, back],
        looksLikeExternalName: (_) => false,
      ),
      [external, front, back],
    );
    expect(
      orderCaptureCamerasExternalFirst(
        cameras: [back, front],
        looksLikeExternalName: (_) => false,
      ),
      [front, back],
    );
  });

  test('orderCaptureCamerasExternalFirst uses name heuristic', () {
    const hdmi = CameraDescription(
      name: 'HDMI Capture Card',
      lensDirection: CameraLensDirection.back,
      sensorOrientation: 0,
    );
    expect(
      orderCaptureCamerasExternalFirst(
        cameras: [front, hdmi],
        looksLikeExternalName: (name) => name.contains('HDMI'),
      ),
      [hdmi, front],
    );
  });

  test('kioskHasCachedExternalCamera true for TV with cached external', () {
    expect(
      kioskHasCachedExternalCamera(
        cached: [external],
        deviceType: AppDeviceType.androidTv,
        looksLikeExternalName: (_) => false,
      ),
      isTrue,
    );
    expect(
      kioskHasCachedExternalCamera(
        cached: [front],
        deviceType: AppDeviceType.androidTv,
        looksLikeExternalName: (_) => false,
      ),
      isFalse,
    );
    expect(
      kioskHasCachedExternalCamera(
        cached: [external],
        deviceType: AppDeviceType.androidPhone,
        looksLikeExternalName: (_) => false,
      ),
      isFalse,
    );
    const hdmi = CameraDescription(
      name: 'HDMI Capture Card',
      lensDirection: CameraLensDirection.back,
      sensorOrientation: 0,
    );
    expect(
      kioskHasCachedExternalCamera(
        cached: [hdmi],
        deviceType: AppDeviceType.iosTablet,
        looksLikeExternalName: (name) => name.contains('HDMI'),
      ),
      isTrue,
    );
  });

  test('shouldShowNoCameraConnectedMessage only when nothing is attached', () {
    expect(
      shouldShowNoCameraConnectedMessage(
        enumeratedCamerasEmpty: true,
        uvcDevicesEmpty: true,
      ),
      isTrue,
    );
    expect(
      shouldShowNoCameraConnectedMessage(
        enumeratedCamerasEmpty: true,
        uvcDevicesEmpty: false,
      ),
      isFalse,
    );
    expect(
      shouldShowNoCameraConnectedMessage(
        enumeratedCamerasEmpty: false,
        uvcDevicesEmpty: true,
      ),
      isFalse,
    );
  });

  test('isPickerEnumeratedCameraChecked marks the live CameraX row', () {
    expect(
      isPickerEnumeratedCameraChecked(
        cameraName: 'Front',
        currentCameraName: 'Front',
        uvcPreviewActive: false,
      ),
      isTrue,
    );
    expect(
      isPickerEnumeratedCameraChecked(
        cameraName: 'Back',
        currentCameraName: 'Front',
        uvcPreviewActive: false,
      ),
      isFalse,
    );
    expect(
      isPickerEnumeratedCameraChecked(
        cameraName: 'Front',
        currentCameraName: 'Front',
        uvcPreviewActive: true,
      ),
      isFalse,
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

  group('CaptureViewModel.hasOpenableCaptureCamera', () {
    tearDown(CaptureViewModel.resetCameraCacheForTest);

    test('returns false when cache is empty', () {
      CaptureViewModel.resetCameraCacheForTest();
      expect(CaptureViewModel.hasOpenableCaptureCamera(), isFalse);
    });

    test('returns true when cached front camera exists on web', () {
      CaptureViewModel.setCachedCamerasForTest([front]);
      expect(CaptureViewModel.hasOpenableCaptureCamera(), isTrue);
    });

    test('returns true when cached USB camera exists on a phone', () {
      CaptureViewModel.setCachedCamerasForTest([external]);
      expect(
        CaptureViewModel.hasOpenableCaptureCamera(
          deviceType: AppDeviceType.iosPhone,
        ),
        isTrue,
      );
    });

    test('returns true when cached external camera exists for kiosk', () {
      CaptureViewModel.setCachedCamerasForTest([external, front]);
      expect(
        CaptureViewModel.hasOpenableCaptureCamera(
          deviceType: AppDeviceType.androidTv,
        ),
        isTrue,
      );
    });
  });
}
