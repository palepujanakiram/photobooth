import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/app_settings_model.dart';
import 'package:photobooth/utils/app_runtime_config.dart';
import 'package:photobooth/utils/uvc_capture_config.dart';
import 'package:uvccamera/uvccamera.dart';

void main() {
  tearDown(() {
    AppRuntimeConfig.instance.applyFromSettings(
      AppSettingsModel(showGenerationCommentary: false),
    );
  });

  test('UvcCaptureConfig uses stability-first profile defaults', () {
    expect(UvcCaptureConfig.resolutionPreset, UvcCameraResolutionPreset.medium);
    expect(UvcCaptureConfig.normalizeMaxDimension, 1024);
    expect(UvcCaptureConfig.normalizeJpegQuality, 75);
    expect(UvcCaptureConfig.postDisposeDelay, const Duration(milliseconds: 750));
    expect(UvcCaptureConfig.reopenFeedDelay, const Duration(milliseconds: 1200));
    expect(UvcCaptureConfig.preCaptureSettleDelay, const Duration(milliseconds: 50));
    expect(UvcCaptureConfig.captureFlashDuration, const Duration(milliseconds: 120));
    expect(UvcCaptureConfig.uiCaptureCooldown, const Duration(milliseconds: 600));
    expect(UvcCaptureConfig.keepControllerOpenDuringReview, isFalse);
    expect(UvcCaptureConfig.previewWarmupPeriod, const Duration(milliseconds: 1500));
    expect(UvcCaptureConfig.shutterGracePeriod, const Duration(seconds: 4));
    expect(UvcCaptureConfig.takePictureTimeout, const Duration(seconds: 10));
    expect(
      UvcCaptureConfig.interruptTakePictureTimeout,
      const Duration(seconds: 10),
    );
    expect(UvcCaptureConfig.deferUploadPrepUntilContinue, isTrue);
    expect(UvcCaptureConfig.enableSessionRecycle, isTrue);
    expect(
      UvcCaptureConfig.sessionRecyclePeriod,
      const Duration(minutes: 8),
    );
    expect(
      UvcCaptureConfig.sessionRecycleRetryDelay,
      const Duration(minutes: 2),
    );
    expect(UvcCaptureConfig.idleSleepPeriod, const Duration(seconds: 45));
    expect(UvcCaptureConfig.idleSleepEnabled, isTrue);
    expect(UvcCaptureConfig.lifecyclePauseEnabled, isTrue);
    expect(UvcCaptureConfig.thermalReliefEnabled, isFalse);
  });

  test('thermalReliefEnabled when thermalSafeMode or commentary kiosk mode', () {
    expect(UvcCaptureConfig.thermalReliefEnabled, isFalse);

    AppRuntimeConfig.instance.applyFromSettings(
      AppSettingsModel(thermalSafeMode: true),
    );
    expect(UvcCaptureConfig.thermalReliefEnabled, isTrue);

    AppRuntimeConfig.instance.applyFromSettings(
      AppSettingsModel(showGenerationCommentary: true),
    );
    expect(UvcCaptureConfig.thermalReliefEnabled, isTrue);
  });
}
