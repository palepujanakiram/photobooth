import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

import '../../utils/app_device_type.dart';

/// Whether [camera] is an external / UVC / HDMI capture device.
bool isExternalCaptureCamera(
  CameraDescription camera,
  bool Function(String name) looksLikeExternalName,
) {
  return camera.lensDirection == CameraLensDirection.external ||
      looksLikeExternalName(camera.name);
}

/// Resolution preset for still capture + preview (kiosk memory vs HDMI reliability).
///
/// Built-in cameras use [veryHigh] so MacBook / phone stills match the live
/// feed better. FotoFlashback can request [max] via [preferPrintQuality].
/// Non-TV USB webcams use [high] so ImageCapture (and stream fallback) stay sharp;
/// Android TV stays [medium] for RAM.
ResolutionPreset captureResolutionPreset({
  required AppDeviceType? deviceType,
  required bool isExternal,
  bool preferPrintQuality = false,
}) {
  if (deviceType == AppDeviceType.androidTv) {
    return ResolutionPreset.medium;
  }
  if (isExternal) {
    return preferPrintQuality
        ? ResolutionPreset.veryHigh
        : ResolutionPreset.high;
  }
  if (preferPrintQuality) {
    return ResolutionPreset.max;
  }
  return ResolutionPreset.veryHigh;
}

/// Stream format: YUV on Android TV / external for single-frame fallback capture.
ImageFormatGroup captureStreamFormat({
  required AppDeviceType? deviceType,
  required bool isExternal,
}) {
  final useYuv = !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      (deviceType == AppDeviceType.androidTv || isExternal);
  return useYuv ? ImageFormatGroup.yuv420 : ImageFormatGroup.jpeg;
}
