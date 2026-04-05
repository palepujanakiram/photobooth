import 'camera_details.dart';

/// Web implementation: returns default values. Real implementation can be added later.
Future<CameraDetails?> getCameraDetails(String cameraId) async {
  return CameraDetails.defaultValues(platform: 'web');
}
