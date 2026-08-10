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

    test('keeps HDMI live when sidecar DSLR owns the still', () {
      expect(
        uvcShouldMaskHdmiDuringStill(
          hasCapturedPhoto: false,
          isCapturing: true,
          captureInFlight: true,
          hdmiStillMaskArmed: true,
          isCountingDown: false,
          countdownValue: null,
          keepHdmiLiveForSidecarStill: true,
        ),
        isFalse,
      );
      expect(
        uvcShouldMaskHdmiDuringStill(
          hasCapturedPhoto: false,
          isCapturing: false,
          captureInFlight: false,
          hdmiStillMaskArmed: true,
          isCountingDown: true,
          countdownValue: 1,
          keepHdmiLiveForSidecarStill: true,
        ),
        isFalse,
      );
    });
  });

  group('captureStillInProgressLabel', () {
    test('sidecar prepare phase asks guests to wait for camera setup', () {
      expect(
        captureStillInProgressLabel(
          usesSidecarDslr: true,
          preparingCamera: true,
        ),
        'Setting up camera…',
      );
    });

    test('sidecar shutter phase prompts Say cheese', () {
      expect(
        captureStillInProgressLabel(
          usesSidecarDslr: true,
          isCapturing: true,
        ),
        'Say cheese!',
      );
    });

    test('sidecar default (armed but not phased) still prompts Say cheese', () {
      expect(
        captureStillInProgressLabel(usesSidecarDslr: true),
        'Say cheese!',
      );
    });

    test('plain UVC keeps Capturing copy', () {
      expect(
        captureStillInProgressLabel(usesSidecarDslr: false),
        'Capturing…',
      );
    });
  });

  group('uvcHdmiPoseCountdownCanContinue', () {
    test('requires pose-ready before prepare-still', () {
      expect(
        uvcHdmiPoseCountdownCanContinue(
          uvcControllerReady: true,
          captureInFlight: false,
          hasCapturedPhoto: false,
          poseReadyForCountdown: false,
          sidecarStillPrepStarted: false,
        ),
        isFalse,
      );
      expect(
        uvcHdmiPoseCountdownCanContinue(
          uvcControllerReady: true,
          captureInFlight: false,
          hasCapturedPhoto: false,
          poseReadyForCountdown: true,
          sidecarStillPrepStarted: false,
        ),
        isTrue,
      );
    });

    test('stays true after prepare-still even when LV pose-ready is false', () {
      expect(
        uvcHdmiPoseCountdownCanContinue(
          uvcControllerReady: true,
          captureInFlight: false,
          hasCapturedPhoto: false,
          poseReadyForCountdown: false,
          sidecarStillPrepStarted: true,
        ),
        isTrue,
      );
    });
  });

  group('uvcHdmiPoseMayFireSidecarStill', () {
    test('blocks pre-prep shutter without LV hold', () {
      expect(
        uvcHdmiPoseMayFireSidecarStill(
          sidecarConfigured: true,
          canonLvHolding: false,
          sidecarStillPrepStarted: false,
        ),
        isFalse,
      );
    });

    test('allows shutter after prepare-still without LV hold', () {
      expect(
        uvcHdmiPoseMayFireSidecarStill(
          sidecarConfigured: true,
          canonLvHolding: false,
          sidecarStillPrepStarted: true,
        ),
        isTrue,
      );
    });
  });
}
