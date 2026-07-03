import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:uvccamera/uvccamera.dart';

import 'app_device_type.dart';
import 'app_runtime_config.dart';
import 'constants.dart';

/// Tunable levers for USB/DSLR (UVC) capture on memory-constrained tablets.
///
/// Built-in cameras use 1920 px / quality 85 from `image_helper.dart`.
/// UVC is capped separately because the plugin saves full preview frames at JPEG quality 100.
///
/// **Profiles** (adjust here after kiosk testing):
/// | Profile     | preset | maxDimension | jpegQuality | uploadPrepDelay |
/// |-------------|--------|--------------|-------------|-----------------|
/// | Performance | min    | 1280         | 80          | 450 ms          |
/// | Balanced    | low    | 1536         | 85          | 300 ms          |
/// | Quality     | medium | 1920         | 85          | 48 ms           |
/// | **Active**  | medium | 1024         | 75          | 450 ms          |
///
/// **Active profile:** 720p preview (not 1080p), 1024px still normalize.
class UvcCaptureConfig {
  UvcCaptureConfig._(); // coverage:ignore-line

  /// Native UVC preview / still stream target (~1280×720 via plugin `medium` preset).
  ///
  /// The `uvccamera` plugin does not expose FPS; the driver picks frame rate for the
  /// negotiated format (often 30 fps at 720p MJPEG on capture cards).
  static const UvcCameraResolutionPreset resolutionPreset =
      UvcCameraResolutionPreset.medium;

  /// TV boxes negotiate more reliably at 640×480 (`low`).
  static UvcCameraResolutionPreset resolutionPresetFor(AppDeviceType? deviceType) {
    if (deviceType == AppDeviceType.androidTv) {
      return UvcCameraResolutionPreset.low;
    }
    return resolutionPreset;
  }

  /// Max long edge after Dart-side normalize.
  static const int normalizeMaxDimension = 1024;

  /// JPEG quality after normalize.
  static const int normalizeJpegQuality = 75;

  /// Pause after UVC dispose before reading the still (lets USB/GPU buffers free).
  static const Duration postDisposeDelay = Duration(milliseconds: 750);

  /// Extra pause before reopening live feed after capture/close (native release).
  static const Duration reopenFeedDelay = Duration(milliseconds: 1200);

  /// Ignore USB `disconnected` events shortly after an intentional native close.
  static const Duration reconnectIgnoreDisconnectPeriod =
      Duration(seconds: 3);

  /// Auto-reconnect attempts before showing a stable error (tap Retry).
  static const int maxAutoReconnectAttempts = 5;

  /// Android TV: longer USB settle time before reopening the feed.
  static Duration reopenFeedDelayFor(AppDeviceType? deviceType) {
    if (deviceType == AppDeviceType.androidTv) {
      return const Duration(milliseconds: 2200);
    }
    return reopenFeedDelay;
  }

  /// Periodic session recycle is disabled on TV — teardown/reopen churn is unstable.
  static bool enableSessionRecycleFor(AppDeviceType? deviceType) {
    if (deviceType == AppDeviceType.androidTv) return false;
    return enableSessionRecycle;
  }

  /// Brief white shutter flash (not held for the whole takePicture wait).
  static const Duration captureFlashDuration = Duration(milliseconds: 120);

  /// Minimum gap between UI captures on the same open feed (native USB release).
  static const Duration uiCaptureCooldown = Duration(milliseconds: 600);

  /// Brief settle before takePicture on a freshly reopened feed.
  static const Duration preCaptureSettleDelay = Duration(milliseconds: 50);

  /// When true, keep the UVC session open while reviewing a still (retake reuses it).
  ///
  /// Always false on production kiosks: closing the native feed during review
  /// cuts CPU/heat and avoids Android PlatformView overlaying the captured still.
  static const bool keepControllerOpenDuringReview = false;

  /// Ignore preview-interrupt shutter signals right after the feed reconnects.
  static const Duration previewWarmupPeriod = Duration(milliseconds: 1500);

  /// Ignore USB disconnect/reconnect churn while the DSLR shutter pauses HDMI.
  static const Duration shutterGracePeriod = Duration(seconds: 4);

  /// Max wait for [UvcCameraController.takePicture] (DSLR bodies can be slow).
  static const Duration takePictureTimeout = Duration(seconds: 10);

  /// Longer wait when the DSLR pauses HDMI — next frame may arrive after review.
  static const Duration interruptTakePictureTimeout = Duration(seconds: 10);

  /// Delay between takePicture retries after preview interrupt (DSLR review frame).
  static const Duration interruptTakePictureRetryDelay =
      Duration(milliseconds: 350);

  /// Pause before upload encode + face detection (when not deferred to Continue).
  static const Duration uploadPrepDelay = Duration(milliseconds: 450);

  /// When true, skip background encode + face detection until the user taps Continue.
  /// Reduces RAM spikes and UI jank while reviewing the captured still on low-RAM tablets.
  static const bool deferUploadPrepUntilContinue = true;

  /// Periodic full UVC teardown + reopen while idle on the live feed (driver leak mitigation).
  static const bool enableSessionRecycle = true;

  /// Interval between idle session recycles (stop preview → release → reopen).
  static const Duration sessionRecyclePeriod = Duration(minutes: 8);

  /// When recycle is deferred (capture in flight, reviewing, etc.), retry after this delay.
  static const Duration sessionRecycleRetryDelay = Duration(minutes: 2);

  /// UVC thermal relief from `/api/settings` or low-memory kiosk mode.
  static bool get thermalReliefEnabled =>
      !kIsWeb &&
      (AppRuntimeConfig.instance.thermalSafeMode ||
          AppConstants.kLowMemoryKioskMode);

  /// Close the live UVC feed after [idleSleepPeriod] with no capture activity.
  static bool get idleSleepEnabled => !kIsWeb;

  /// Idle time before closing the live feed (tap preview to reopen).
  static const Duration idleSleepPeriod = Duration(seconds: 45);

  /// Close UVC when the app is backgrounded; reopen on resume.
  static bool get lifecyclePauseEnabled => !kIsWeb;
}
