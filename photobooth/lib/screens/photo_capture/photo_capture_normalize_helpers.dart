import '../../utils/image_helper.dart';
import '../../utils/uvc_capture_config.dart';

/// JPEG quality for [ImageHelper.normalizeAndSaveCapturedPhoto].
///
/// Thermal relief still wins on UVC. Classic strip uses print-oriented quality
/// for both built-in and UVC (HDMI) stills.
int? captureNormalizeJpegQuality({
  required bool isUvc,
  required bool preferStripPrintQuality,
}) {
  if (isUvc && UvcCaptureConfig.thermalReliefEnabled) {
    return UvcCaptureConfig.effectiveNormalizeJpegQuality;
  }
  if (preferStripPrintQuality) {
    return kStripCapturedPhotoJpegQuality;
  }
  if (isUvc) {
    return UvcCaptureConfig.effectiveNormalizeJpegQuality;
  }
  return null;
}

/// Long-edge cap for normalize. Classic strip keeps up to
/// [kStripCapturedPhotoMaxDimension] for UVC as well as built-in (HDMI is
/// usually ≤1920; higher caps are a no-op when the frame is smaller).
int? captureNormalizeMaxDimension({
  required bool isUvc,
  required bool preferStripPrintQuality,
}) {
  if (isUvc && UvcCaptureConfig.thermalReliefEnabled) {
    return UvcCaptureConfig.effectiveNormalizeMaxDimension;
  }
  if (preferStripPrintQuality) {
    return kStripCapturedPhotoMaxDimension;
  }
  if (isUvc) {
    return UvcCaptureConfig.effectiveNormalizeMaxDimension;
  }
  return null;
}
