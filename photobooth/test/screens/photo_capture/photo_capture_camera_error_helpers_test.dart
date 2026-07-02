import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/photo_capture/photo_capture_camera_error_helpers.dart';

void main() {
  test('cameraLoadFailureMessage maps camera unavailable', () {
    final error = PlatformException(
      code: 'ExecutionException',
      message: 'CameraUnavailableException: Available cameras: 0',
    );
    expect(
      cameraLoadFailureMessage(error),
      contains('No camera detected'),
    );
  });

  test('cameraLoadFailureMessage maps failed to open camera', () {
    final error = PlatformException(
      code: 'IllegalStateException',
      message: 'Failed to open camera',
    );
    expect(
      cameraLoadFailureMessage(error),
      contains('unavailable'),
    );
  });

  test('cameraLoadFailureMessage maps missing USB device', () {
    final error = PlatformException(
      code: 'IllegalArgumentException',
      message: 'Device not found: /dev/bus/usb/001/008',
    );
    expect(
      cameraLoadFailureMessage(error),
      contains('USB camera disconnected'),
    );
  });

  test('cameraLoadFailureMessage maps timeout', () {
    expect(
      cameraLoadFailureMessage(TimeoutException('x')),
      contains('too long'),
    );
  });

  test('isHandledCameraPipelineError recognizes camera platform failures', () {
    expect(
      isHandledCameraPipelineError(
        PlatformException(
          code: 'IllegalStateException',
          message: 'Failed to open camera',
        ),
      ),
      isTrue,
    );
    expect(isHandledCameraPipelineError(Exception('unrelated')), isFalse);
  });

  test('cameraLoadFailureMessage handles generic error strings', () {
    expect(
      cameraLoadFailureMessage(Exception('CameraUnavailable: Available cameras: 0')),
      contains('No camera detected'),
    );
    expect(
      cameraLoadFailureMessage(Exception('Failed to open camera')),
      contains('unavailable'),
    );
    expect(
      cameraLoadFailureMessage(Exception('Device not found: /dev/bus/usb/001/008')),
      contains('USB camera disconnected'),
    );
    expect(
      cameraLoadFailureMessage(Exception('something else')),
      'Failed to load cameras. Please try again.',
    );
  });

  test('cameraLoadFailureMessage uses platform fallback for unknown codes', () {
    expect(
      cameraLoadFailureMessage(
        PlatformException(code: 'unknown', message: 'unexpected'),
      ),
      'Camera is unavailable. Please try again.',
    );
  });

  test('isHandledCameraPipelineError matches CameraX zero cameras', () {
    expect(
      isHandledCameraPipelineError(
        PlatformException(
          code: 'ExecutionException',
          message:
              'java.util.concurrent.ExecutionException: '
              'CameraUnavailableException: Available cameras: 0',
        ),
      ),
      isTrue,
    );
  });

  test('isHandledCameraPipelineError matches usb-only platform failures', () {
    expect(
      isHandledCameraPipelineError(Exception('platformexception usb offline')),
      isTrue,
    );
  });
}
