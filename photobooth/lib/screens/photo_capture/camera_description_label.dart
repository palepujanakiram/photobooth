import 'package:camera/camera.dart';

import '../../utils/app_strings.dart';

/// True if [name] looks like a real external device (e.g. iOS UUID).
bool looksLikeExternalCameraName(String name) {
  final lower = name.toLowerCase();
  if (lower.contains('built-in')) return false;
  if (name.length < 10) return false;
  if (name.length > 30 && name.contains('-')) return true;
  return lower.contains('webcam') ||
      lower.contains('usb') ||
      lower.contains('external');
}

bool isExternalCamera(CameraDescription camera) {
  return camera.lensDirection == CameraLensDirection.external ||
      looksLikeExternalCameraName(camera.name);
}

/// Debug label for [CameraDescription] (external vs built-in).
String cameraDescriptionLabel(CameraDescription camera) {
  final tag = isExternalCamera(camera)
      ? AppStrings.cameraLabelExternal
      : AppStrings.cameraLabelBuiltIn;
  return '$tag ${camera.name} (${camera.lensDirection})';
}
