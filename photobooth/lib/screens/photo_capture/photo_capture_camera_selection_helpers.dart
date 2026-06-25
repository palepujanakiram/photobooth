import 'package:camera/camera.dart';

import '../../utils/app_device_type.dart';
import '../../utils/app_strings.dart';
import 'camera_description_label.dart';

/// True when [cameras] includes a USB / HDMI / external device.
bool camerasIncludeExternal(List<CameraDescription> cameras) {
  return cameras.any(isExternalCamera);
}

/// Tablet/TV hint when only built-in cameras are enumerated (USB may need refresh).
String? cameraPickerUsbHint({
  required AppDeviceType? deviceType,
  required List<CameraDescription> cameras,
}) {
  if (deviceType != AppDeviceType.androidTablet &&
      deviceType != AppDeviceType.androidTv) {
    return null;
  }
  if (cameras.isEmpty || camerasIncludeExternal(cameras)) {
    return null;
  }
  return AppStrings.cameraPickerBuiltInOnlyHint;
}

/// One entry per display name (avoids duplicate logical cameras on iOS).
List<CameraDescription> uniqueCamerasByDisplayName(
  List<CameraDescription> cameras,
  String Function(CameraDescription camera) displayNameFor,
) {
  final uniqueCameras = <CameraDescription>[];
  final seenDisplayNames = <String>{};

  for (final camera in cameras) {
    final displayName = displayNameFor(camera);
    if (seenDisplayNames.contains(displayName)) {
      continue;
    }
    seenDisplayNames.add(displayName);
    uniqueCameras.add(camera);
  }

  return uniqueCameras;
}
