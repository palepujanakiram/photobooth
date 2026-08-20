import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/photo_capture/photo_capture_viewmodel.dart';
import 'package:photobooth/utils/app_device_type.dart';
import 'package:photobooth/utils/device_camera_fallback.dart';

void main() {
  tearDown(CaptureViewModel.resetCameraCacheForTest);

  group('shouldPreferDeviceCameraOverDslr', () {
    test('prefers device camera when DSLR path is down', () {
      expect(
        shouldPreferDeviceCameraOverDslr(
          dslrPathCanServe: false,
          hasOpenableDeviceCamera: true,
        ),
        isTrue,
      );
    });

    test('keeps DSLR when it can serve', () {
      expect(
        shouldPreferDeviceCameraOverDslr(
          dslrPathCanServe: true,
          hasOpenableDeviceCamera: true,
        ),
        isFalse,
      );
    });

    test('does not prefer device camera when none enumerated', () {
      expect(
        shouldPreferDeviceCameraOverDslr(
          dslrPathCanServe: false,
          hasOpenableDeviceCamera: false,
        ),
        isFalse,
      );
    });
  });

  group('shouldCommitToSidecarPoseSession', () {
    test('commits when sidecar EVF is healthy', () {
      expect(
        shouldCommitToSidecarPoseSession(
          sidecarReadyOrHealthy: true,
          hasOpenableDeviceCamera: true,
          keepDirectWithoutDeviceFallback: false,
        ),
        isTrue,
      );
    });

    test('falls through to CameraX when process is up but body missing', () {
      expect(
        shouldCommitToSidecarPoseSession(
          sidecarReadyOrHealthy: false,
          hasOpenableDeviceCamera: true,
          keepDirectWithoutDeviceFallback: true,
        ),
        isFalse,
      );
    });

    test('keeps Direct EVF when no device camera is available', () {
      expect(
        shouldCommitToSidecarPoseSession(
          sidecarReadyOrHealthy: false,
          hasOpenableDeviceCamera: false,
          keepDirectWithoutDeviceFallback: true,
        ),
        isTrue,
      );
    });

    test('does not keep blank EVF without keepDirect or health', () {
      expect(
        shouldCommitToSidecarPoseSession(
          sidecarReadyOrHealthy: false,
          hasOpenableDeviceCamera: false,
          keepDirectWithoutDeviceFallback: false,
        ),
        isFalse,
      );
    });
  });

  group('hasOpenableDeviceCaptureCamera', () {
    test('delegates to CaptureViewModel enumeration cache', () {
      CaptureViewModel.resetCameraCacheForTest();
      expect(hasOpenableDeviceCaptureCamera(), isFalse);
      CaptureViewModel.setCachedCamerasForTest([
        const CameraDescription(
          name: '0',
          lensDirection: CameraLensDirection.back,
          sensorOrientation: 90,
        ),
      ]);
      expect(hasOpenableDeviceCaptureCamera(), isTrue);
      expect(
        hasOpenableDeviceCaptureCamera(
          deviceType: AppDeviceType.androidPhone,
        ),
        isTrue,
      );
    });
  });
}
