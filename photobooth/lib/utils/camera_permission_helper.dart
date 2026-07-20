import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform, visibleForTesting;

import 'package:permission_handler/permission_handler.dart';

/// Android / iOS kiosk and phone builds that use [Permission.camera].
bool get isNativeMobileCameraPlatform {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}

/// Returns true when camera access is granted (requests when [requestIfNeeded]).
Future<bool> ensureCameraPermission({bool requestIfNeeded = true}) async {
  return ensureCameraPermissionForPlatform(
    isNativeMobile: isNativeMobileCameraPlatform,
    requestIfNeeded: requestIfNeeded,
  );
}

/// Platform-aware camera permission gate (unit-testable on the VM).
@visibleForTesting
Future<bool> ensureCameraPermissionForPlatform({
  required bool isNativeMobile,
  bool requestIfNeeded = true,
  Future<PermissionStatus> Function()? readStatus,
  Future<PermissionStatus> Function()? requestPermission,
}) async {
  if (!isNativeMobile) return true;

  final status =
      readStatus != null ? await readStatus() : await Permission.camera.status;
  if (status.isGranted) return true;
  if (!requestIfNeeded) return false;

  final result = requestPermission != null
      ? await requestPermission()
      : await Permission.camera.request();
  return result.isGranted;
}

/// Called when Terms opens so POSE does not show the system dialog mid-flow.
Future<void> primeCameraPermissionOnTermsLaunch() async {
  await ensureCameraPermission();
}
