import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/photo_capture/photo_capture_pose_setup_helpers.dart';
import 'package:photobooth/utils/app_device_type.dart';
import 'package:photobooth/utils/uvc_capture_config.dart';

void main() {
  test('uvcPoseEntryOpenTimeout is longer on kiosk devices', () {
    expect(
      uvcPoseEntryOpenTimeout(AppDeviceType.androidTv),
      UvcCaptureConfig.openTimeout + const Duration(seconds: 4),
    );
    expect(
      uvcPoseEntryOpenTimeout(AppDeviceType.androidPhone),
      UvcCaptureConfig.quickOpenTimeout,
    );
  });

  test('shouldAdoptTermsPrewarmOnPoseInit on phones only', () {
    expect(shouldAdoptTermsPrewarmOnPoseInit(AppDeviceType.androidPhone), isTrue);
    expect(shouldAdoptTermsPrewarmOnPoseInit(AppDeviceType.androidTv), isFalse);
    expect(shouldAdoptTermsPrewarmOnPoseInit(null), isTrue);
  });

  test('shouldSkipUvcNormalizeOnKiosk is never true (BGR fix required)', () {
    expect(shouldSkipUvcNormalizeOnKiosk(AppDeviceType.androidTv), isFalse);
    expect(shouldSkipUvcNormalizeOnKiosk(AppDeviceType.androidTablet), isFalse);
    expect(shouldSkipUvcNormalizeOnKiosk(AppDeviceType.androidPhone), isFalse);
    expect(shouldSkipUvcNormalizeOnKiosk(null), isFalse);
  });

  test('shouldSkipTermsCameraPrewarm on kiosk devices only', () {
    expect(shouldSkipTermsCameraPrewarm(AppDeviceType.androidTv), isTrue);
    expect(shouldSkipTermsCameraPrewarm(AppDeviceType.androidTablet), isTrue);
    expect(shouldSkipTermsCameraPrewarm(AppDeviceType.androidPhone), isFalse);
    expect(shouldSkipTermsCameraPrewarm(null), isFalse);
  });

  test('kioskShouldTryUvcBeforeCameraX for TV and tablet only', () {
    expect(kioskShouldTryUvcBeforeCameraX(AppDeviceType.androidTv), isTrue);
    expect(kioskShouldTryUvcBeforeCameraX(AppDeviceType.androidTablet), isTrue);
    expect(kioskShouldTryUvcBeforeCameraX(AppDeviceType.androidPhone), isFalse);
    expect(kioskShouldTryUvcBeforeCameraX(AppDeviceType.iosPhone), isFalse);
    expect(kioskShouldTryUvcBeforeCameraX(null), isFalse);
  });

  test('shouldDeferUploadPrepUntilContinue on TV and UVC ids', () {
    expect(
      shouldDeferUploadPrepUntilContinue(
        deviceType: AppDeviceType.androidTv,
        cameraId: 'Camera 0',
      ),
      isTrue,
    );
    expect(
      shouldDeferUploadPrepUntilContinue(
        deviceType: AppDeviceType.androidPhone,
        cameraId: 'uvc:123:456:Webcam',
      ),
      isTrue,
    );
    expect(
      shouldDeferUploadPrepUntilContinue(
        deviceType: AppDeviceType.androidPhone,
        cameraId: 'Camera 0',
      ),
      isFalse,
    );
  });

  test('shouldSkipClientFaceDetectionForUpload on kiosks', () {
    expect(
      shouldSkipClientFaceDetectionForUpload(
        deviceType: AppDeviceType.androidTv,
        cameraId: 'Camera 0',
      ),
      isTrue,
    );
    expect(
      shouldSkipClientFaceDetectionForUpload(
        deviceType: AppDeviceType.androidPhone,
        cameraId: 'uvc:1:2:x',
      ),
      isTrue,
    );
  });
}
