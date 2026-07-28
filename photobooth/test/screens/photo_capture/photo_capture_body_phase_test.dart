import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/photo_capture/photo_capture_body_phase.dart';

void main() {
  group('isCapturePreviewStarting', () {
    test('false when a photo is already captured', () {
      expect(
        isCapturePreviewStarting(
          hasCapturedPhoto: true,
          isDesktopCaptureMode: false,
          isLoadingCameras: true,
          isInitializing: true,
          isUsingUvc: false,
          uvcInitializing: false,
          uvcOpeningController: false,
          uvcControllerReady: false,
          camerasEmpty: false,
          isReady: false,
        ),
        isFalse,
      );
    });

    test('desktop only waits on camera list load', () {
      expect(
        isCapturePreviewStarting(
          hasCapturedPhoto: false,
          isDesktopCaptureMode: true,
          isLoadingCameras: true,
          isInitializing: false,
          isUsingUvc: false,
          uvcInitializing: false,
          uvcOpeningController: false,
          uvcControllerReady: false,
          camerasEmpty: true,
          isReady: false,
        ),
        isTrue,
      );
      expect(
        isCapturePreviewStarting(
          hasCapturedPhoto: false,
          isDesktopCaptureMode: true,
          isLoadingCameras: false,
          isInitializing: true,
          isUsingUvc: false,
          uvcInitializing: false,
          uvcOpeningController: false,
          uvcControllerReady: false,
          camerasEmpty: true,
          isReady: false,
        ),
        isFalse,
      );
    });

    test('stops starting once cameras are empty after load', () {
      expect(
        isCapturePreviewStarting(
          hasCapturedPhoto: false,
          isDesktopCaptureMode: false,
          isLoadingCameras: false,
          isInitializing: false,
          isUsingUvc: false,
          uvcInitializing: false,
          uvcOpeningController: false,
          uvcControllerReady: false,
          camerasEmpty: true,
          isReady: false,
        ),
        isFalse,
      );
    });

    test('stays starting while enumeration or init is in progress', () {
      expect(
        isCapturePreviewStarting(
          hasCapturedPhoto: false,
          isDesktopCaptureMode: false,
          isLoadingCameras: true,
          isInitializing: false,
          isUsingUvc: false,
          uvcInitializing: false,
          uvcOpeningController: false,
          uvcControllerReady: false,
          camerasEmpty: true,
          isReady: false,
        ),
        isTrue,
      );
      expect(
        isCapturePreviewStarting(
          hasCapturedPhoto: false,
          isDesktopCaptureMode: false,
          isLoadingCameras: false,
          isInitializing: true,
          isUsingUvc: false,
          uvcInitializing: false,
          uvcOpeningController: false,
          uvcControllerReady: false,
          camerasEmpty: false,
          isReady: false,
        ),
        isTrue,
      );
    });

    test('UVC waits until controller is ready', () {
      expect(
        isCapturePreviewStarting(
          hasCapturedPhoto: false,
          isDesktopCaptureMode: false,
          isLoadingCameras: false,
          isInitializing: false,
          isUsingUvc: true,
          uvcInitializing: true,
          uvcOpeningController: false,
          uvcControllerReady: false,
          camerasEmpty: true,
          isReady: false,
        ),
        isTrue,
      );
      expect(
        isCapturePreviewStarting(
          hasCapturedPhoto: false,
          isDesktopCaptureMode: false,
          isLoadingCameras: false,
          isInitializing: false,
          isUsingUvc: true,
          uvcInitializing: false,
          uvcOpeningController: true,
          uvcControllerReady: false,
          camerasEmpty: true,
          isReady: false,
        ),
        isTrue,
      );
      expect(
        isCapturePreviewStarting(
          hasCapturedPhoto: false,
          isDesktopCaptureMode: false,
          isLoadingCameras: false,
          isInitializing: false,
          isUsingUvc: true,
          uvcInitializing: false,
          uvcOpeningController: false,
          uvcControllerReady: false,
          camerasEmpty: true,
          isReady: false,
        ),
        isTrue,
      );
      expect(
        isCapturePreviewStarting(
          hasCapturedPhoto: false,
          isDesktopCaptureMode: false,
          isLoadingCameras: false,
          isInitializing: false,
          isUsingUvc: true,
          uvcInitializing: false,
          uvcOpeningController: false,
          uvcControllerReady: true,
          camerasEmpty: true,
          isReady: false,
        ),
        isFalse,
      );
    });

    test('waits for camera ready when cameras exist', () {
      expect(
        isCapturePreviewStarting(
          hasCapturedPhoto: false,
          isDesktopCaptureMode: false,
          isLoadingCameras: false,
          isInitializing: false,
          isUsingUvc: false,
          uvcInitializing: false,
          uvcOpeningController: false,
          uvcControllerReady: false,
          camerasEmpty: false,
          isReady: false,
        ),
        isTrue,
      );
      expect(
        isCapturePreviewStarting(
          hasCapturedPhoto: false,
          isDesktopCaptureMode: false,
          isLoadingCameras: false,
          isInitializing: false,
          isUsingUvc: false,
          uvcInitializing: false,
          uvcOpeningController: false,
          uvcControllerReady: false,
          camerasEmpty: false,
          isReady: true,
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
