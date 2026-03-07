import 'src/camera_details.dart';
import 'src/camera_native_details_io.dart'
    if (dart.library.html) 'src/camera_native_details_web.dart' as impl;

export 'src/camera_details.dart';

/// Plugin to get native camera characteristics.
///
/// On Android: returns Camera2 data (active array, zoom range, supported sizes).
/// On iOS and Web: returns default/placeholder values for now.
class CameraNativeDetails {
  /// Fetches camera details for the given [cameraId].
  ///
  /// [cameraId] should match the camera identifier used by the camera plugin
  /// (e.g. on Android this is typically "0", "1", or the external camera id).
  /// Returns null on error or if the camera is not found.
  static Future<CameraDetails?> getCameraDetails(String cameraId) {
    return impl.getCameraDetails(cameraId);
  }
}
