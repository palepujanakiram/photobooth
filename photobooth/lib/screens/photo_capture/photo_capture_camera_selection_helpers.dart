import 'package:camera/camera.dart';

import '../../utils/app_device_type.dart';
import '../../utils/app_strings.dart';
import '../../utils/device_classifier.dart';
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

/// Filters enumerated cameras for kiosk vs phone (tablet/TV → external only).
List<CameraDescription> camerasForDeviceType({
  required List<CameraDescription> cameras,
  required AppDeviceType? deviceType,
  required bool Function(String name) looksLikeExternalName,
}) {
  if (deviceType == null) return cameras;
  if (DeviceClassifier.showOnlyExternalCameras(deviceType)) {
    return cameras
        .where(
          (c) =>
              c.lensDirection == CameraLensDirection.external ||
              looksLikeExternalName(c.name),
        )
        .toList();
  }
  switch (deviceType) {
    case AppDeviceType.androidPhone:
    case AppDeviceType.iosPhone:
      return cameras
          .where(
            (c) =>
                c.lensDirection != CameraLensDirection.external &&
                !looksLikeExternalName(c.name),
          )
          .toList();
    default:
      return cameras;
  }
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
