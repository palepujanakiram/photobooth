import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'app_strings.dart';
import 'logger.dart';

/// Which camera stack the event hub will use for Capture.
enum EventCaptureKind {
  /// Nothing this runtime can shoot with.
  none,

  /// Tethered Canon on USB (native PTP Activity).
  ptp,

  /// Built-in camera or webcam via the device camera picker.
  device,
}

/// Names and labels for the event hub's device-camera fallback.
abstract final class EventDeviceCameras {
  /// Operator-facing name when Capture will use this device, not a Canon.
  static String labelFor({bool? isWeb}) =>
      (isWeb ?? kIsWeb) ? AppStrings.eventHubWebcam : AppStrings.eventHubPhoneCamera;

  /// Camera plugin ids, or empty when none are attached / the plugin is missing.
  ///
  /// Never throws: a readiness probe that crashed would take the hub down, and
  /// "no camera" is already a row the operator can act on.
  static Future<List<String>> listNames({
    Future<List<String>> Function()? enumerate,
  }) async {
    try {
      if (enumerate != null) return await enumerate();
      final cameras = await availableCameras();
      return [for (final camera in cameras) camera.name];
    } catch (e) {
      AppLogger.debug('Device cameras unavailable: $e');
      return const <String>[];
    }
  }
}
