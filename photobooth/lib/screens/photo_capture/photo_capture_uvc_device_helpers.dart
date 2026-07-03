import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:permission_handler/permission_handler.dart';
import 'package:uvccamera/uvccamera.dart';

/// True when [a] and [b] refer to the same physical UVC device.
bool uvcDeviceMatches(UvcCameraDevice a, UvcCameraDevice b) {
  return a.vendorId == b.vendorId &&
      a.productId == b.productId &&
      a.name == b.name;
}

/// Camera permission must be granted before UVC device permission (plugin requirement).
Future<bool> ensureAndroidCameraPermissionForUvc() async {
  if (defaultTargetPlatform != TargetPlatform.android) return false;
  final cameraStatus = await Permission.camera.status;
  if (cameraStatus.isGranted) return true;
  final requested = await Permission.camera.request();
  return requested.isGranted;
}

/// Camera permission must be granted before UVC device permission (plugin requirement).
Future<bool> ensureUvcPermissions(UvcCameraDevice device) async {
  if (defaultTargetPlatform != TargetPlatform.android) return false;
  if (!await ensureAndroidCameraPermissionForUvc()) return false;
  try {
    return await UvcCamera.requestDevicePermission(device);
  } catch (_) {
    return false;
  }
}

/// Loads the first attached UVC / USB camera on Android, or null when unavailable.
Future<UvcCameraDevice?> probeFirstUvcDevice({
  bool requestCameraPermission = false,
}) async {
  if (defaultTargetPlatform != TargetPlatform.android) return null;
  try {
    if (!await UvcCamera.isSupported()) return null;
    if (requestCameraPermission &&
        !await ensureAndroidCameraPermissionForUvc()) {
      return null;
    }
    final devices = await UvcCamera.getDevices();
    if (devices.isEmpty) return null;
    return devices.values.first;
  } catch (_) {
    return null;
  }
}

/// Resolves a hotplug event device to a live entry from [UvcCamera.getDevices].
Future<UvcCameraDevice?> resolveUvcDeviceForHotplug(
  UvcCameraDevice preferred, {
  bool requestCameraPermission = false,
}) async {
  if (defaultTargetPlatform != TargetPlatform.android) return null;
  try {
    if (!await UvcCamera.isSupported()) return null;
    if (requestCameraPermission &&
        !await ensureAndroidCameraPermissionForUvc()) {
      return null;
    }
    final devices = await UvcCamera.getDevices();
    for (final device in devices.values) {
      if (uvcDeviceMatches(device, preferred)) return device;
    }
    if (devices.isNotEmpty) return devices.values.first;
    return null;
  } catch (_) {
    return null;
  }
}
