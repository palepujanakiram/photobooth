import '../../../utils/logger.dart';
import '../../direct_ptp_camera_service.dart';
import 'event_capture_source.dart';

/// [EventCaptureSource] over the existing Direct PTP / EDSDK native stack.
///
/// **The native screen is the capture screen.** `runCaptureSession` launches
/// `CanonCaptureActivity`, which already owns live view, the shutter, and a
/// retake/accept review — so this hands the whole interaction to it rather than
/// wrapping it in a second one. Anything else produces the flow this replaced:
/// a Dart screen, then a native screen over the top of it, then a Dart review
/// of a shot the native screen had already reviewed.
///
/// Live view stays native for a measured reason. It draws straight into a
/// `SurfaceView` via `lockCanvas`, which is a hardware overlay plane and the
/// cheapest path Android has. Bringing it into Flutter means a `Texture`, which
/// is a copy per frame plus an engine recomposite — a cost this codebase
/// already rejected for rounded corners, on a box that needs Impeller off.
class DirectPtpCaptureSource implements EventCaptureSource {
  DirectPtpCaptureSource({DirectPtpCameraService? service})
      : _service = service ?? DirectPtpCameraService();

  final DirectPtpCameraService _service;

  /// The operator's session: shutter-driven, no countdown, no guest uploads.
  ///
  /// `reviewHoldMs: 0` holds the shot on screen indefinitely with Retake and
  /// Accept, which is the confirm step — so there is no second one in Dart.
  static DirectPtpCaptureRequest requestFor({
    String? title,
    String? subtitle,
    String? ink,
    String? accent,
    String? background,
  }) {
    return DirectPtpCaptureRequest(
      shotCount: 1,
      countdownSeconds: 0,
      autoStart: false,
      reviewHoldMs: 0,
      idleTimeoutSeconds: 3600,
      allowGalleryUpload: false,
      allowPhoneUpload: false,
      showCountdownHeadline: false,
      titleText: title,
      subtitleText: subtitle,
      shutterText: 'Capture',
      cancelText: 'Done',
      inkColor: ink,
      accentColor: accent,
      backgroundColor: background,
    );
  }

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

  /// Event chrome for the native screen, set before [shoot].
  DirectPtpCaptureRequest _request = requestFor();

  set request(DirectPtpCaptureRequest value) => _request = value;

  @override
  Future<CapturedShot?> shoot() async {
    final result = await _service.runCaptureSession(_request);
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
