import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/utils/uvc_capture_config.dart';
import 'package:uvccamera/uvccamera.dart';

void main() {
  test('UvcCaptureConfig uses stability-first profile defaults', () {
    expect(UvcCaptureConfig.resolutionPreset, UvcCameraResolutionPreset.min);
    expect(UvcCaptureConfig.normalizeMaxDimension, 1024);
    expect(UvcCaptureConfig.normalizeJpegQuality, 75);
    expect(UvcCaptureConfig.postDisposeDelay, const Duration(milliseconds: 750));
    expect(UvcCaptureConfig.reopenFeedDelay, const Duration(milliseconds: 1200));
    expect(UvcCaptureConfig.preCaptureSettleDelay, const Duration(milliseconds: 50));
    expect(UvcCaptureConfig.captureFlashDuration, const Duration(milliseconds: 120));
    expect(UvcCaptureConfig.uiCaptureCooldown, const Duration(milliseconds: 600));
    expect(UvcCaptureConfig.keepControllerOpenDuringReview, isTrue);
    expect(UvcCaptureConfig.previewWarmupPeriod, const Duration(milliseconds: 1500));
    expect(UvcCaptureConfig.shutterGracePeriod, const Duration(seconds: 4));
    expect(UvcCaptureConfig.takePictureTimeout, const Duration(seconds: 10));
    expect(
      UvcCaptureConfig.interruptTakePictureTimeout,
      const Duration(seconds: 10),
    );
    expect(UvcCaptureConfig.deferUploadPrepUntilContinue, isTrue);
  });
}
