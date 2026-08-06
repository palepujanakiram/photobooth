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

/// Best-effort: arm Canon Live View for HDMI/UVC pose (no still).
///
/// Pose uses the capture card; LV must be on over USB or HDMI stays blank
/// until someone presses Q on the body. Safe no-op when sidecar is unset.
Future<void> ensureCanonLiveViewForHdmiPose(LocalCameraService? service) async {
  if (service == null || !service.isConfigured) return;
  try {
    final result = await service.ensureLiveView();
    AppLogger.info(
      'Canon LV ensure: enabled=${result.enabled} woke=${result.woke}',
    );
  } catch (e) {
    AppLogger.warning('Canon LV ensure failed (HDMI may stay blank): $e');
  }
}

/// Tries FotoZen Pi sidecar still capture; returns null to use CameraX/UVC.
///
/// Writes JPEG bytes to a temp file on native so review/upload have a real
/// path (XFile.fromData left path empty and forced a full in-memory decode of
/// multi‑MP DSLR stills that hung the kiosk).
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

/// Persist a DSLR sidecar JPEG for review with EXIF (+ live-feed sync turns).
///
/// Full-resolution Canon stills (often 20MP+) hang [compute] normalize on
/// Android TV past both the 20s normalize and 45s overall capture budgets —
/// [Future.timeout] cannot cancel an in-flight isolate decode. Sidecar already
/// downscales (~1920 long edge), so a light EXIF bake + matching the live feed
/// ([liveFeedSyncedCaptureQuarterTurns]) is safe and keeps strip/print upright.
Future<XFile> persistSidecarCaptureStill(
  XFile rawFile, {
  int bakeQuarterTurns = 0,
}) async {
  if (kIsWeb) {
    return rawFile;
  }
  XFile source = rawFile;
  if (rawFile.path.isEmpty) {
    final bytes = await rawFile.readAsBytes();
    if (bytes.isEmpty) {
      throw Exception('Sidecar capture is empty');
    }
    final tempDir = await FileHelper.getTempDirectoryPath();
    final dir = '$tempDir/sidecar';
    await FileHelper.ensureDirectory(dir);
    final path =
        '$dir/fz200d_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final file = FileHelper.createFile(path);
    await (file as dynamic).writeAsBytes(bytes, flush: true);
    source = XFile(path, mimeType: 'image/jpeg');
  }
  final turns = ((bakeQuarterTurns % 4) + 4) % 4;
  AppLogger.info(
    turns == 0
        ? 'Persisting sidecar still with EXIF bake (skip full normalize)'
        : 'Persisting sidecar still with EXIF bake + ${turns * 90}° '
            '(skip full normalize)',
  );
  return ImageHelper.bakeExifAndQuarterTurns(
    source,
    quarterTurns: turns,
  );
}
