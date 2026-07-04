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

/// Tablet/TV kiosk with a pre-enumerated external Camera2 device (Terms preload).
bool kioskHasCachedExternalCamera({
  required List<CameraDescription>? cached,
  required AppDeviceType? deviceType,
  required bool Function(String name) looksLikeExternalName,
}) {
  if (cached == null || cached.isEmpty || deviceType == null) return false;
  if (!DeviceClassifier.showOnlyExternalCameras(deviceType)) return false;
  return camerasForDeviceType(
    cameras: cached,
    deviceType: deviceType,
    looksLikeExternalName: looksLikeExternalName,
  ).isNotEmpty;
}

/// Cameras to open on POSE: **external first**, then any other connected camera.
///
/// Phones keep built-in-only filtering. Kiosk/tablet/TV prefers USB/HDMI but falls
/// back to built-in when no external is enumerated yet (fast preview from Terms cache).
List<CameraDescription> captureCamerasForDevice({
  required List<CameraDescription> cameras,
  required AppDeviceType? deviceType,
  required bool Function(String name) looksLikeExternalName,
}) {
  if (cameras.isEmpty) return cameras;

  if (deviceType == AppDeviceType.androidPhone ||
      deviceType == AppDeviceType.iosPhone) {
    return camerasForDeviceType(
      cameras: cameras,
      deviceType: deviceType,
      looksLikeExternalName: looksLikeExternalName,
    );
  }

  if (deviceType != null &&
      DeviceClassifier.showOnlyExternalCameras(deviceType)) {
    final external = cameras
        .where(
          (c) =>
              c.lensDirection == CameraLensDirection.external ||
              looksLikeExternalName(c.name),
        )
        .toList();
    if (external.isNotEmpty) return external;
    return List<CameraDescription>.from(cameras);
  }

  return orderCaptureCamerasExternalFirst(
    cameras: cameras,
    looksLikeExternalName: looksLikeExternalName,
  );
}

/// External / USB / HDMI entries first, then built-in cameras.
List<CameraDescription> orderCaptureCamerasExternalFirst({
  required List<CameraDescription> cameras,
  required bool Function(String name) looksLikeExternalName,
}) {
  final external = <CameraDescription>[];
  final other = <CameraDescription>[];
  for (final camera in cameras) {
    if (camera.lensDirection == CameraLensDirection.external ||
        looksLikeExternalName(camera.name)) {
      external.add(camera);
    } else {
      other.add(camera);
    }
  }
  return [...external, ...other];
}

/// Default camera from an enumerated list (external preferred).
CameraDescription pickPreferredCaptureCamera({
  required List<CameraDescription> cameras,
  required AppDeviceType? deviceType,
  required bool Function(String name) looksLikeExternalName,
}) {
  final candidates = captureCamerasForDevice(
    cameras: cameras,
    deviceType: deviceType,
    looksLikeExternalName: looksLikeExternalName,
  );
  if (candidates.isEmpty) {
    throw StateError('No cameras available');
  }
  return candidates.first;
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
