import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/photo_capture/photo_capture_pose_setup_helpers.dart';
import 'package:photobooth/utils/app_device_type.dart';
import 'package:photobooth/utils/uvc_capture_config.dart';

void main() {
  test('uvcPoseEntryOpenTimeout is longer on kiosk devices', () {
    expect(
      uvcPoseEntryOpenTimeout(AppDeviceType.androidTv),
      UvcCaptureConfig.openTimeout + const Duration(seconds: 2),
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

  test('kioskShouldSkipCameraXWhenUvcUnavailable on kiosk TV and tablet', () {
    expect(
      kioskShouldSkipCameraXWhenUvcUnavailable(AppDeviceType.androidTv),
      isTrue,
    );
    expect(
      kioskShouldSkipCameraXWhenUvcUnavailable(AppDeviceType.androidTablet),
      isTrue,
    );
    expect(
      kioskShouldSkipCameraXWhenUvcUnavailable(AppDeviceType.androidPhone),
      isFalse,
    );
    expect(kioskShouldSkipCameraXWhenUvcUnavailable(null), isFalse);
    expect(
      kioskShouldSkipCameraXWhenUvcUnavailable(
        AppDeviceType.androidPhone,
        sidecarConfigured: true,
      ),
      isTrue,
    );
    expect(
      kioskShouldSkipCameraXWhenUvcUnavailable(
        AppDeviceType.androidTablet,
        sidecarConfigured: true,
        preferDeviceCameraFallback: true,
      ),
      isFalse,
    );
  });

  test('shouldFotoZenFallThroughToDeviceCameraAfterUvcMiss', () {
    expect(
      shouldFotoZenFallThroughToDeviceCameraAfterUvcMiss(
        isClassic: false,
        uvcAttached: false,
        sidecarConfigured: false,
      ),
      isTrue,
    );
    expect(
      shouldFotoZenFallThroughToDeviceCameraAfterUvcMiss(
        isClassic: true,
        uvcAttached: false,
        sidecarConfigured: false,
      ),
      isFalse,
    );
    expect(
      shouldFotoZenFallThroughToDeviceCameraAfterUvcMiss(
        isClassic: false,
        uvcAttached: false,
        sidecarConfigured: true,
      ),
      isFalse,
    );
    expect(
      shouldFotoZenFallThroughToDeviceCameraAfterUvcMiss(
        isClassic: false,
        uvcAttached: true,
        sidecarConfigured: false,
      ),
      isFalse,
    );
  });

  test('shouldStartSidecarPreviewAfterUvcMiss when sidecar is configured', () {
    expect(
      shouldStartSidecarPreviewAfterUvcMiss(sidecarConfigured: true),
      isTrue,
    );
    expect(
      shouldStartSidecarPreviewAfterUvcMiss(sidecarConfigured: false),
      isFalse,
    );
  });

  test('shouldSkipUvcProbeForSidecarPose when DSLR sidecar can serve pose', () {
    expect(
      shouldSkipUvcProbeForSidecarPose(
        sidecarConfigured: true,
        uvcWebcamAttached: false,
      ),
      isTrue,
    );
    expect(
      shouldSkipUvcProbeForSidecarPose(
        sidecarConfigured: true,
        uvcWebcamAttached: true,
      ),
      isFalse,
    );
    expect(
      shouldSkipUvcProbeForSidecarPose(
        sidecarConfigured: false,
        uvcWebcamAttached: false,
      ),
      isFalse,
    );
  });

  test('shouldWaitHdmiSettleAfterCanonLv only for capture-card pose', () {
    expect(
      shouldWaitHdmiSettleAfterCanonLv(sidecarIsPosePreview: true),
      isFalse,
    );
    expect(
      shouldWaitHdmiSettleAfterCanonLv(sidecarIsPosePreview: false),
      isTrue,
    );
  });

  test('shouldKeepDirectSidecarPose only for configured USB EDSDK', () {
    expect(
      shouldKeepDirectSidecarPose(
        isDirectConnection: true,
        hasSidecarEndpoint: true,
      ),
      isTrue,
    );
    expect(
      shouldKeepDirectSidecarPose(
        isDirectConnection: true,
        hasSidecarEndpoint: true,
        preferDeviceCameraFallback: true,
      ),
      isFalse,
    );
    expect(
      shouldKeepDirectSidecarPose(
        isDirectConnection: true,
        hasSidecarEndpoint: false,
      ),
      isFalse,
    );
    expect(
      shouldKeepDirectSidecarPose(
        isDirectConnection: false,
        hasSidecarEndpoint: true,
      ),
      isFalse,
    );
  });

  test('shouldSwitchInferredPiToDirect only when Pi was inferred and is down',
      () {
    expect(
      shouldSwitchInferredPiToDirect(
        isPiConnection: true,
        modeExplicit: false,
        piListening: false,
        nativeSidecarRunning: true,
      ),
      isTrue,
    );
    expect(
      shouldSwitchInferredPiToDirect(
        isPiConnection: true,
        modeExplicit: true,
        piListening: false,
        nativeSidecarRunning: true,
      ),
      isFalse,
    );
    expect(
      shouldSwitchInferredPiToDirect(
        isPiConnection: true,
        modeExplicit: false,
        piListening: true,
        nativeSidecarRunning: true,
      ),
      isFalse,
    );
    expect(
      shouldSwitchInferredPiToDirect(
        isPiConnection: false,
        modeExplicit: false,
        piListening: false,
        nativeSidecarRunning: true,
      ),
      isFalse,
    );
    expect(
      shouldSwitchInferredPiToDirect(
        isPiConnection: true,
        modeExplicit: false,
        piListening: false,
        nativeSidecarRunning: false,
      ),
      isFalse,
    );
  });

  test('shouldKeepPoseStartingForExternalSource only while a source exists', () {
    expect(
      shouldKeepPoseStartingForExternalSource(
        uvcWebcamAttached: true,
        sidecarConfigured: false,
      ),
      isTrue,
    );
    expect(
      shouldKeepPoseStartingForExternalSource(
        uvcWebcamAttached: false,
        sidecarConfigured: true,
      ),
      isTrue,
    );
    expect(
      shouldKeepPoseStartingForExternalSource(
        uvcWebcamAttached: false,
        sidecarConfigured: true,
        preferDeviceCameraFallback: true,
      ),
      isFalse,
    );
    expect(
      shouldKeepPoseStartingForExternalSource(
        uvcWebcamAttached: false,
        sidecarConfigured: false,
      ),
      isFalse,
    );
  });

  test('shouldForceSidecarLivePreview is off (HDMI pose preferred)', () {
    expect(shouldForceSidecarLivePreview(sidecarConfigured: true), isFalse);
    expect(shouldForceSidecarLivePreview(sidecarConfigured: false), isFalse);
  });

  test('shouldUseSidecarPosePreview honors admin live preview for Classic + AI',
      () {
    expect(
      shouldUseSidecarPosePreview(
        classicSession: true,
        sidecarLivePreviewEnabled: true,
        sidecarConfigured: true,
      ),
      isTrue,
    );
    expect(
      shouldUseSidecarPosePreview(
        classicSession: true,
        sidecarLivePreviewEnabled: false,
        sidecarConfigured: true,
      ),
      isFalse,
    );
    expect(
      shouldUseSidecarPosePreview(
        classicSession: true,
        sidecarLivePreviewEnabled: false,
        sidecarConfigured: true,
        classicSidecarFallback: true,
      ),
      isTrue,
    );
    expect(
      shouldUseSidecarPosePreview(
        classicSession: false,
        sidecarLivePreviewEnabled: true,
        sidecarConfigured: true,
      ),
      isTrue,
    );
    expect(
      shouldUseSidecarPosePreview(
        classicSession: false,
        sidecarLivePreviewEnabled: false,
        sidecarConfigured: true,
      ),
      isFalse,
    );
    expect(
      shouldUseSidecarPosePreview(
        classicSession: true,
        sidecarLivePreviewEnabled: true,
        sidecarConfigured: false,
      ),
      isFalse,
    );
  });

  test('capturePhotoUploadActionsAllowed matches settings with strip guard', () {
    expect(
      capturePhotoUploadActionsAllowed(
        photoUploadAllowed: true,
        classicFourShotInProgress: false,
      ),
      isTrue,
    );
    expect(
      capturePhotoUploadActionsAllowed(
        photoUploadAllowed: false,
        classicFourShotInProgress: false,
      ),
      isFalse,
    );
    expect(
      capturePhotoUploadActionsAllowed(
        photoUploadAllowed: true,
        classicFourShotInProgress: true,
      ),
      isFalse,
    );
  });

  test('poseReviewStillBoxFit covers sidecar stills', () {
    expect(
      poseReviewStillBoxFit(sidecarPosePreview: true),
      BoxFit.cover,
    );
    expect(
      poseReviewStillBoxFit(sidecarPosePreview: false),
      BoxFit.contain,
    );
  });

  test('poseReviewStillSharpDisplay on sidecar pose', () {
    expect(
      poseReviewStillSharpDisplay(
        sidecarPosePreview: true,
        deviceType: AppDeviceType.androidPhone,
      ),
      isTrue,
    );
    expect(
      poseReviewStillSharpDisplay(
        sidecarPosePreview: false,
        deviceType: AppDeviceType.androidTv,
      ),
      isFalse,
    );
    expect(
      poseReviewStillSharpDisplay(
        sidecarPosePreview: false,
        deviceType: AppDeviceType.androidPhone,
      ),
      isTrue,
    );
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
    expect(
      shouldDeferUploadPrepUntilContinue(
        deviceType: AppDeviceType.androidPhone,
        cameraId: 'sidecar:FZ200D',
      ),
      isTrue,
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
    expect(
      shouldSkipClientFaceDetectionForUpload(
        deviceType: AppDeviceType.androidPhone,
        cameraId: 'sidecar:FZ200D',
      ),
      isTrue,
    );
  });
}
