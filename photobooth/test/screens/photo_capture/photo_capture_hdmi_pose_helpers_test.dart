import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/photo_capture/photo_capture_hdmi_pose_helpers.dart';

void main() {
  group('uvcHdmiPoseReadyForCountdown', () {
    test('requires initialized UVC and no in-flight capture', () {
      expect(
        uvcHdmiPoseReadyForCountdown(
          uvcControllerReady: false,
          captureInFlight: false,
          previewWarmupActive: false,
          sidecarConfigured: false,
          canonLvHolding: false,
        ),
        isFalse,
      );
      expect(
        uvcHdmiPoseReadyForCountdown(
          uvcControllerReady: true,
          captureInFlight: true,
          previewWarmupActive: false,
          sidecarConfigured: false,
          canonLvHolding: false,
        ),
        isFalse,
      );
    });

    test('waits out HDMI warmup before countdown', () {
      expect(
        uvcHdmiPoseReadyForCountdown(
          uvcControllerReady: true,
          captureInFlight: false,
          previewWarmupActive: true,
          sidecarConfigured: false,
          canonLvHolding: false,
        ),
        isFalse,
      );
    });

    test('plain UVC webcam does not require Canon LV hold', () {
      expect(
        uvcHdmiPoseReadyForCountdown(
          uvcControllerReady: true,
          captureInFlight: false,
          previewWarmupActive: false,
          sidecarConfigured: false,
          canonLvHolding: false,
        ),
        isTrue,
      );
    });

    test('sidecar booth requires Canon LV hold (avoids blank until Q)', () {
      expect(
        uvcHdmiPoseReadyForCountdown(
          uvcControllerReady: true,
          captureInFlight: false,
          previewWarmupActive: false,
          sidecarConfigured: true,
          canonLvHolding: false,
        ),
        isFalse,
      );
      expect(
        uvcHdmiPoseReadyForCountdown(
          uvcControllerReady: true,
          captureInFlight: false,
          previewWarmupActive: false,
          sidecarConfigured: true,
          canonLvHolding: true,
        ),
        isTrue,
      );
    });

    test('in-flight still blocks countdown; mask alone is a separate concern', () {
      // Callers must not pass hdmiStillMaskArmed as captureInFlight — that
      // aborted shutter after onCountdownFinished armed the mask.
      expect(
        uvcHdmiPoseReadyForCountdown(
          uvcControllerReady: true,
          captureInFlight: false,
          previewWarmupActive: false,
          sidecarConfigured: true,
          canonLvHolding: true,
        ),
        isTrue,
      );
    });
  });

  group('uvcShouldMaskHdmiDuringStill', () {
    test('masks while capturing or in-flight', () {
      expect(
        uvcShouldMaskHdmiDuringStill(
          hasCapturedPhoto: false,
          isCapturing: true,
          captureInFlight: false,
          hdmiStillMaskArmed: false,
          isCountingDown: false,
          countdownValue: null,
        ),
        isTrue,
      );
      expect(
        uvcShouldMaskHdmiDuringStill(
          hasCapturedPhoto: false,
          isCapturing: false,
          captureInFlight: true,
          hdmiStillMaskArmed: false,
          isCountingDown: false,
          countdownValue: null,
        ),
        isTrue,
      );
    });

    test('masks when armed after countdown clears', () {
      expect(
        uvcShouldMaskHdmiDuringStill(
          hasCapturedPhoto: false,
          isCapturing: false,
          captureInFlight: false,
          hdmiStillMaskArmed: true,
          isCountingDown: false,
          countdownValue: null,
        ),
        isTrue,
      );
    });

    test('masks on last countdown tick', () {
      expect(
        uvcShouldMaskHdmiDuringStill(
          hasCapturedPhoto: false,
          isCapturing: false,
          captureInFlight: false,
          hdmiStillMaskArmed: false,
          isCountingDown: true,
          countdownValue: 1,
        ),
        isTrue,
      );
      expect(
        uvcShouldMaskHdmiDuringStill(
          hasCapturedPhoto: false,
          isCapturing: false,
          captureInFlight: false,
          hdmiStillMaskArmed: false,
          isCountingDown: true,
          countdownValue: 3,
        ),
        isFalse,
      );
    });

    test('never masks once a review still is assigned', () {
      expect(
        uvcShouldMaskHdmiDuringStill(
          hasCapturedPhoto: true,
          isCapturing: true,
          captureInFlight: true,
          hdmiStillMaskArmed: true,
          isCountingDown: false,
          countdownValue: null,
        ),
        isFalse,
      );
    });
  });

  group('captureStillInProgressLabel', () {
    test('sidecar DSLR asks guests to hold still through LV teardown clicks', () {
      expect(
        captureStillInProgressLabel(usesSidecarDslr: true),
        'Hold still…',
      );
    });

    test('plain UVC keeps Capturing copy', () {
      expect(
        captureStillInProgressLabel(usesSidecarDslr: false),
        'Capturing…',
      );
    });
  });
}
