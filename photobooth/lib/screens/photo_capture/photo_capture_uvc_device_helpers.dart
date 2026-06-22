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
Future<bool> ensureUvcPermissions(UvcCameraDevice device) async {
  if (defaultTargetPlatform != TargetPlatform.android) return false;
  final cameraStatus = await Permission.camera.status;
  if (!cameraStatus.isGranted) {
    final requested = await Permission.camera.request();
    if (!requested.isGranted) return false;
  }
  return UvcCamera.requestDevicePermission(device);
}

/// Loads the first attached UVC / USB camera on Android, or null when unavailable.
Future<UvcCameraDevice?> probeFirstUvcDevice() async {
  if (defaultTargetPlatform != TargetPlatform.android) return null;
  try {
    if (!await UvcCamera.isSupported()) return null;
    final devices = await UvcCamera.getDevices();
    if (devices.isEmpty) return null;
    return devices.values.first;
  } catch (_) {
    return null;
  }
}
