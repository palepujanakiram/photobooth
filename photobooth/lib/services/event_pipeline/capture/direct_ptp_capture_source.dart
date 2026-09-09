import '../../../utils/logger.dart';
import '../../direct_ptp_camera_service.dart';
import 'event_capture_source.dart';

/// [EventCaptureSource] over the existing Direct PTP / EDSDK native stack.
///
/// A one-shot session per press: `shotCount: 1`, no countdown, no auto-start
/// and no review hold, so the native screen fires and returns immediately
/// rather than running the guest flow. The review is this screen's job, because
/// Confirm here means something the guest flow's review does not — it commits
/// the frame to the event queue.
class DirectPtpCaptureSource implements EventCaptureSource {
  DirectPtpCaptureSource({DirectPtpCameraService? service})
      : _service = service ?? DirectPtpCameraService();

  final DirectPtpCameraService _service;

  /// A photographer presses the shutter on the camera body; the operator
  /// presses this. Neither wants a countdown.
  static const DirectPtpCaptureRequest request = DirectPtpCaptureRequest(
    shotCount: 1,
    countdownSeconds: 0,
    autoStart: true,
    reviewHoldMs: 1,
    idleTimeoutSeconds: 60,
  );

  @override
  Future<String?> cameraName() async {
    try {
      final device = await _service.probeDevice();
      if (device == null) return null;
      final product = device.product?.trim() ?? '';
      return product.isEmpty ? device.deviceName : product;
    } catch (e) {
      AppLogger.debug('Capture camera probe failed: $e');
      return null;
    }
  }

  @override
  Future<CapturedShot?> shoot() async {
    final result = await _service.runCaptureSession(request);
    if (result.status != DirectPtpCaptureStatus.completed) {
      AppLogger.warning('Capture did not complete: ${result.status}');
      return null;
    }
    final shots = result.shots;
    if (shots.isEmpty) return null;
    final shot = shots.first;
    if (shot.originalPath.trim().isEmpty) return null;
    return CapturedShot(
      originalPath: shot.originalPath,
      previewPath: shot.displayPath,
      capturedAtMs: shot.capturedAtMs == 0
          ? DateTime.now().millisecondsSinceEpoch
          : shot.capturedAtMs,
      width: shot.widthPx,
      height: shot.heightPx,
      bytes: shot.bytes,
    );
  }

  @override
  Future<void> dispose() => _service.disconnect();
}
