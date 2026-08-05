import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/photo_capture/photo_capture_body_phase.dart';

bool _starting({
  bool hasCapturedPhoto = false,
  bool isDesktopCaptureMode = false,
  bool isLoadingCameras = false,
  bool isInitializing = false,
  bool isCapturing = false,
  bool isUsingUvc = false,
  bool uvcHoldLivePreviewClosed = false,
  bool uvcInitializing = false,
  bool uvcOpeningController = false,
  bool uvcControllerReady = false,
  bool camerasEmpty = false,
  bool isReady = false,
  bool cameraSetupStalled = false,
}) {
  return isCapturePreviewStarting(
    hasCapturedPhoto: hasCapturedPhoto,
    isDesktopCaptureMode: isDesktopCaptureMode,
    isLoadingCameras: isLoadingCameras,
    isInitializing: isInitializing,
    isCapturing: isCapturing,
    isUsingUvc: isUsingUvc,
    uvcHoldLivePreviewClosed: uvcHoldLivePreviewClosed,
    uvcInitializing: uvcInitializing,
    uvcOpeningController: uvcOpeningController,
    uvcControllerReady: uvcControllerReady,
    camerasEmpty: camerasEmpty,
    isReady: isReady,
    cameraSetupStalled: cameraSetupStalled,
  );
}

void main() {
  group('isCapturePreviewStarting', () {
    test('false when a photo is already captured', () {
      expect(
        _starting(
          hasCapturedPhoto: true,
          isLoadingCameras: true,
          isInitializing: true,
          isReady: false,
        ),
        isFalse,
      );
    });

    test('false while capture or UVC review is in progress', () {
      expect(_starting(isCapturing: true, isUsingUvc: true), isFalse);
      expect(
        _starting(
          isUsingUvc: true,
          uvcHoldLivePreviewClosed: true,
          uvcControllerReady: false,
        ),
        isFalse,
      );
    });

    test('false when camera setup stalled with an error path', () {
      expect(
        _starting(
          camerasEmpty: false,
          isReady: false,
          cameraSetupStalled: true,
        ),
        isFalse,
      );
    });

    test('desktop only waits on camera list load', () {
      expect(
        _starting(isDesktopCaptureMode: true, isLoadingCameras: true),
        isTrue,
      );
      expect(
        _starting(
          isDesktopCaptureMode: true,
          isInitializing: true,
          camerasEmpty: true,
        ),
        isFalse,
      );
    });

    test('stops starting once cameras are empty after load', () {
      expect(_starting(camerasEmpty: true), isFalse);
    });

    test('stays starting while isLoadingCameras during Classic remount', () {
      expect(
        _starting(isLoadingCameras: true, camerasEmpty: true),
        isTrue,
      );
    });

    test('stays starting while enumeration or init is in progress', () {
      expect(
        _starting(isLoadingCameras: true, camerasEmpty: true),
        isTrue,
      );
      expect(_starting(isInitializing: true), isTrue);
    });

    test('UVC waits until controller is ready', () {
      expect(
        _starting(isUsingUvc: true, uvcInitializing: true, camerasEmpty: true),
        isTrue,
      );
      expect(
        _starting(
          isUsingUvc: true,
          uvcOpeningController: true,
          camerasEmpty: true,
        ),
        isTrue,
      );
      expect(
        _starting(isUsingUvc: true, camerasEmpty: true),
        isTrue,
      );
      expect(
        _starting(
          isUsingUvc: true,
          uvcControllerReady: true,
          camerasEmpty: true,
        ),
        isFalse,
      );
    });

    test('waits for camera ready when cameras exist', () {
      expect(_starting(isReady: false), isTrue);
      expect(_starting(isReady: true), isFalse);
    });

    test('sidecar live preview is not stuck in starting spinner', () {
      expect(
        isCapturePreviewStarting(
          hasCapturedPhoto: false,
          isDesktopCaptureMode: false,
          isLoadingCameras: false,
          isInitializing: false,
          isCapturing: false,
          isUsingUvc: false,
          uvcHoldLivePreviewClosed: false,
          uvcInitializing: false,
          uvcOpeningController: false,
          uvcControllerReady: false,
          camerasEmpty: true,
          isReady: false,
          usesSidecarLivePreview: true,
        ),
        isFalse,
      );
    });
  });

  group('resolveCaptureBodyPhase', () {
    test('starting takes priority', () {
      expect(
        resolveCaptureBodyPhase(
          isPreviewStarting: true,
          camerasEmpty: true,
          hasError: true,
          isUsingUvc: false,
          hasCapturedPhoto: false,
        ),
        CaptureBodyPhase.starting,
      );
    });

    test('prefers noCameras over error when list is empty', () {
      expect(
        resolveCaptureBodyPhase(
          isPreviewStarting: false,
          camerasEmpty: true,
          hasError: true,
          isUsingUvc: false,
          hasCapturedPhoto: false,
        ),
        CaptureBodyPhase.noCameras,
      );
    });

    test('sidecar live preview stays live even with empty camera list', () {
      expect(
        resolveCaptureBodyPhase(
          isPreviewStarting: false,
          camerasEmpty: true,
          hasError: false,
          isUsingUvc: false,
          hasCapturedPhoto: false,
          usesSidecarLivePreview: true,
        ),
        CaptureBodyPhase.live,
      );
    });

    test('keeps live review after gallery upload with no camera', () {
      expect(
        resolveCaptureBodyPhase(
          isPreviewStarting: false,
          camerasEmpty: true,
          hasError: false,
          isUsingUvc: false,
          hasCapturedPhoto: true,
        ),
        CaptureBodyPhase.live,
      );
    });

    test('shows selecting placeholder via live while gallery picker open', () {
      expect(
        resolveCaptureBodyPhase(
          isPreviewStarting: false,
          camerasEmpty: true,
          hasError: false,
          isUsingUvc: false,
          hasCapturedPhoto: false,
          isSelectingFromGallery: true,
        ),
        CaptureBodyPhase.live,
      );
    });

    test('shows error when cameras exist but hasError', () {
      expect(
        resolveCaptureBodyPhase(
          isPreviewStarting: false,
          camerasEmpty: false,
          hasError: true,
          isUsingUvc: false,
          hasCapturedPhoto: false,
        ),
        CaptureBodyPhase.error,
      );
    });

    test('live when camera path is healthy', () {
      expect(
        resolveCaptureBodyPhase(
          isPreviewStarting: false,
          camerasEmpty: false,
          hasError: false,
          isUsingUvc: false,
          hasCapturedPhoto: false,
        ),
        CaptureBodyPhase.live,
      );
    });
  });

  group('shouldProbeUvcAfterNoCameraX', () {
    test('skips when UVC already healthy or CameraX ready', () {
      expect(
        shouldProbeUvcAfterNoCameraX(
          photoUploadAllowed: false,
          camerasEmpty: true,
          uvcFeedHealthy: true,
          cameraReady: false,
        ),
        isFalse,
      );
      expect(
        shouldProbeUvcAfterNoCameraX(
          photoUploadAllowed: false,
          camerasEmpty: true,
          uvcFeedHealthy: false,
          cameraReady: true,
        ),
        isFalse,
      );
    });

    test('skips UVC probe when upload allowed and no cameras', () {
      expect(
        shouldProbeUvcAfterNoCameraX(
          photoUploadAllowed: true,
          camerasEmpty: true,
          uvcFeedHealthy: false,
          cameraReady: false,
        ),
        isFalse,
      );
    });

    test('allows UVC probe when upload is disabled', () {
      expect(
        shouldProbeUvcAfterNoCameraX(
          photoUploadAllowed: false,
          camerasEmpty: true,
          uvcFeedHealthy: false,
          cameraReady: false,
        ),
        isTrue,
      );
    });

    test('false when cameras are not empty', () {
      expect(
        shouldProbeUvcAfterNoCameraX(
          photoUploadAllowed: false,
          camerasEmpty: false,
          uvcFeedHealthy: false,
          cameraReady: false,
        ),
        isFalse,
      );
    });
  });
}
