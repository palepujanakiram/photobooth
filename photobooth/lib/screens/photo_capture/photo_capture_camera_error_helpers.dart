import 'dart:async';

import 'package:flutter/services.dart';

/// User-facing message for camera enumeration / open failures.
String cameraLoadFailureMessage(Object error) {
  if (error is TimeoutException) {
    return 'Camera took too long to load. Please try again.';
  }
  if (error is PlatformException) {
    return _platformCameraFailureMessage(error);
  }
  final text = error.toString().toLowerCase();
  if (text.contains('available cameras: 0') ||
      text.contains('cameraunavailable')) {
    return 'No camera detected. Connect a camera or use Gallery if enabled.';
  }
  if (text.contains('failed to open camera')) {
    return 'Camera is unavailable. Try again or select another camera.';
  }
  if (text.contains('device not found')) {
    return 'USB camera disconnected. Reconnect and tap Retry.';
  }
  return 'Failed to load cameras. Please try again.';
}

String _platformCameraFailureMessage(PlatformException error) {
  final text = '${error.code} ${error.message}'.toLowerCase();
  if (text.contains('available cameras: 0') ||
      text.contains('cameraunavailable') ||
      text.contains('executionexception')) {
    return 'No camera detected. Connect a camera or use Gallery if enabled.';
  }
  if (text.contains('failed to open camera') ||
      text.contains('illegalstateexception')) {
    return 'Camera is unavailable. Try again or select another camera.';
  }
  if (text.contains('device not found') ||
      text.contains('illegalargumentexception')) {
    return 'USB camera disconnected. Reconnect and tap Retry.';
  }
  return 'Camera is unavailable. Please try again.';
}

/// Non-fatal camera pipeline errors already surfaced on the capture screen.
bool isHandledCameraPipelineError(Object error) {
  final text = error.toString().toLowerCase();
  return text.contains('camerunavailable') ||
      text.contains('available cameras: 0') ||
      text.contains('failed to open camera') ||
      text.contains('device not found') ||
      text.contains('failed to load cameras') ||
      text.contains('failed to initialize camera') ||
      text.contains('failed to initialize usb camera') ||
      text.contains('usb camera') ||
      (text.contains('illegalstateexception') && text.contains('camera')) ||
      (text.contains('platformexception') &&
          (text.contains('camera') || text.contains('usb')));
}
