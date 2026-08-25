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
  return cached.any(
    (camera) =>
        camera.lensDirection == CameraLensDirection.external ||
        looksLikeExternalName(camera.name),
  );
}

/// Cameras shown on POSE and Select Camera: **every attached device**.
///
/// Order is external / USB / HDMI first, then the front built-in camera, then
/// remaining cameras. [deviceType] is kept so call sites stay stable; listing
/// is the same on every device.
List<CameraDescription> captureCamerasForDevice({
  required List<CameraDescription> cameras,
  required AppDeviceType? deviceType,
  required bool Function(String name) looksLikeExternalName,
}) {
  assert(() {
    deviceType;
    return true;
  }());
  return orderCaptureCamerasExternalFirst(
    cameras: cameras,
    looksLikeExternalName: looksLikeExternalName,
  );
}

/// External / USB / HDMI first, then front, then remaining built-in cameras.
List<CameraDescription> orderCaptureCamerasExternalFirst({
  required List<CameraDescription> cameras,
  required bool Function(String name) looksLikeExternalName,
}) {
  final external = <CameraDescription>[];
  final front = <CameraDescription>[];
  final other = <CameraDescription>[];
  for (final camera in cameras) {
    if (camera.lensDirection == CameraLensDirection.external ||
        looksLikeExternalName(camera.name)) {
      external.add(camera);
    } else if (camera.lensDirection == CameraLensDirection.front) {
      front.add(camera);
    } else {
      other.add(camera);
    }
  }
  return [...external, ...front, ...other];
}

/// Default POSE camera: attached external if any, otherwise front built-in.
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

/// Same listing as [captureCamerasForDevice] (all attached cameras, ordered).
List<CameraDescription> camerasForDeviceType({
  required List<CameraDescription> cameras,
  required AppDeviceType? deviceType,
  required bool Function(String name) looksLikeExternalName,
}) {
  return captureCamerasForDevice(
    cameras: cameras,
    deviceType: deviceType,
    looksLikeExternalName: looksLikeExternalName,
  );
}

/// True when Select Camera / POSE should show [AppStrings.noCameraConnected].
bool shouldShowNoCameraConnectedMessage({
  required bool enumeratedCamerasEmpty,
  required bool uvcDevicesEmpty,
}) {
  return enumeratedCamerasEmpty && uvcDevicesEmpty;
}

/// Checkmark on Select Camera: enumerated row is active when it is the live
/// CameraX camera and UVC is not the current preview.
bool isPickerEnumeratedCameraChecked({
  required String cameraName,
  required String? currentCameraName,
  required bool uvcPreviewActive,
}) {
  if (uvcPreviewActive) return false;
  return currentCameraName == cameraName;
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
