import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../../services/file_helper.dart';
import '../../services/local_camera_service.dart';
import '../../utils/image_helper.dart';
import '../../utils/logger.dart';

/// True when [cameraId] is a Pi gphoto2 / FZ200D still.
bool isSidecarCameraId(String? cameraId) {
  final id = cameraId?.trim() ?? '';
  return id.startsWith('sidecar:');
}

/// Tries FotoZen Pi sidecar still capture; returns null to use CameraX/UVC.
///
/// Writes JPEG bytes to a temp file on native so normalize/copy have a real
/// path (XFile.fromData left path empty and forced a full in-memory decode of
/// multi‑MP DSLR stills that timed out on Android TV).
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
    AppLogger.info(
      'Captured still from camera sidecar ($name, ${bytes.length} bytes)',
    );
    if (kIsWeb) {
      return XFile.fromData(
        bytes,
        mimeType: 'image/jpeg',
        name: name,
      );
    }
    try {
      final tempDir = await FileHelper.getTempDirectoryPath();
      final dir = '$tempDir/sidecar';
      await FileHelper.ensureDirectory(dir);
      final path = '$dir/$name';
      final file = FileHelper.createFile(path);
      await (file as dynamic).writeAsBytes(bytes, flush: true);
      return XFile(path, mimeType: 'image/jpeg', name: name);
    } catch (writeErr) {
      AppLogger.warning(
        'Sidecar temp write failed; using in-memory still: $writeErr',
      );
      return XFile.fromData(
        bytes,
        mimeType: 'image/jpeg',
        name: name,
      );
    }
  } catch (e) {
    AppLogger.warning('Camera sidecar capture failed; falling back: $e');
    return null;
  }
}

/// Persist a DSLR sidecar JPEG for review without hanging kiosk normalize.
///
/// Tries a bounded downscale to [kCapturedPhotoMaxDimension]; on timeout or
/// failure, copies the camera JPEG into the app photos dir as-is.
Future<XFile> persistSidecarCaptureStill(
  XFile rawFile, {
  Duration normalizeTimeout = const Duration(seconds: 45),
  int maxDimension = kCapturedPhotoMaxDimension,
  int jpegQuality = kCapturedPhotoJpegQuality,
}) async {
  try {
    return await ImageHelper.normalizeAndSaveCapturedPhoto(
      rawFile,
      flipHorizontal: false,
      maxDimension: maxDimension,
      jpegQuality: jpegQuality,
    ).timeout(normalizeTimeout);
  } catch (e) {
    AppLogger.warning(
      'Sidecar normalize failed/timed out; using direct JPEG copy: $e',
    );
    if (kIsWeb || rawFile.path.isEmpty) {
      rethrow;
    }
    return ImageHelper.copyCaptureToAppPhotosDir(rawFile);
  }
}
