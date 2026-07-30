import 'package:camera/camera.dart';

import '../../services/local_camera_service.dart';
import '../../utils/logger.dart';

/// Tries FotoZen Pi sidecar still capture; returns null to use CameraX/UVC.
Future<XFile?> tryCaptureFromSidecar(LocalCameraService? service) async {
  if (service == null || !service.isConfigured) {
    return null;
  }
  try {
    final healthy = await service.isHealthy();
    if (!healthy) {
      AppLogger.info('Camera sidecar not healthy; using local camera');
      return null;
    }
    final bytes = await service.capture();
    if (bytes.isEmpty) return null;
    final name = 'fz200d_${DateTime.now().millisecondsSinceEpoch}.jpg';
    AppLogger.info('Captured still from camera sidecar ($name, ${bytes.length} bytes)');
    return XFile.fromData(
      bytes,
      mimeType: 'image/jpeg',
      name: name,
    );
  } catch (e) {
    AppLogger.warning('Camera sidecar capture failed; falling back: $e');
    return null;
  }
}
