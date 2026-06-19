import 'package:uvccamera/uvccamera.dart';

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
class UvcCaptureConfig {
  UvcCaptureConfig._();

  /// Native UVC stream / still resolution (`min` < `low` < `medium`).
  static const UvcCameraResolutionPreset resolutionPreset =
      UvcCameraResolutionPreset.low;

  /// Max long edge after Dart-side normalize (matches session PATCH cap).
  static const int normalizeMaxDimension = 1536;

  /// JPEG quality after normalize.
  static const int normalizeJpegQuality = 85;

  /// Pause before upload encode + face detection so UVC dispose / GC can run.
  static const Duration uploadPrepDelay = Duration(milliseconds: 300);

  /// When true, skip background encode + face detection until the user taps Continue.
  /// Reduces RAM spikes and UI jank while reviewing the captured still on low-RAM tablets.
  static const bool deferUploadPrepUntilContinue = true;
}
