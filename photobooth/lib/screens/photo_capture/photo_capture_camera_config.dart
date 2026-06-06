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
ResolutionPreset captureResolutionPreset({
  required AppDeviceType? deviceType,
  required bool isExternal,
}) {
  if (deviceType == AppDeviceType.androidTv) {
    return ResolutionPreset.low;
  }
  if (isExternal) {
    return ResolutionPreset.medium;
  }
  return ResolutionPreset.high;
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
