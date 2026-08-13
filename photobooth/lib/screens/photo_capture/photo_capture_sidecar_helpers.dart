import 'dart:async' show unawaited;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;

import '../../services/file_helper.dart';
import '../../services/local_camera_service.dart';
import '../../utils/capture_flow_log.dart';
import '../../utils/image_helper.dart';
import '../../utils/logger.dart';
import '../../utils/sidecar_error_parse.dart';

/// When true, sidecar helpers take the web (in-memory XFile) branches.
@visibleForTesting
bool debugSidecarHelpersForceWeb = false;

bool get _sidecarTreatAsWeb => kIsWeb || debugSidecarHelpersForceWeb;

/// True when [cameraId] is a Pi gphoto2 / FZ200D still.
bool isSidecarCameraId(String? cameraId) {
  final id = cameraId?.trim() ?? '';
  return id.startsWith('sidecar:');
}

/// Classic HDMI booths use Pi for the still; CameraX is often uninitialized.
///
/// Falling through to [CameraController.takePicture] yields `cameraNotReady`
/// and leaves the strip UI stuck after a sidecar miss / dropped JPEG.
bool shouldRefuseCameraxFallbackWhenSidecarMisses({
  required bool sidecarConfigured,
}) =>
    sidecarConfigured;

/// Best-effort: arm Canon Live View for HDMI/UVC pose (no still).
///
/// Pose uses the capture card; LV must stay on over USB or HDMI falls back to
/// the body status / Q menu. Sidecar ≥ v1.2.4 holds LV with a capture-movie
/// session and skips capture-preview wakes (those click the mirror). Safe no-op
/// when sidecar is unset.
///
/// Returns whether LV is enabled and/or held (for shorter HDMI settle/warmup).
Future<({bool ok, bool holding})> ensureCanonLiveViewForHdmiPose(
  LocalCameraService? service,
) async {
  if (service == null || !service.isConfigured) {
    AppLogger.info('[HDMI_POSE] LV ensure skipped — sidecar not configured');
    return (ok: false, holding: false);
  }
  const attempts = 2;
  for (var i = 0; i < attempts; i++) {
    final corrId = service.newCorrId();
    final t0 = DateTime.now();
    try {
      final result = await service.ensureLiveView(corrId: corrId);
      final ms = DateTime.now().difference(t0).inMilliseconds;
      AppLogger.info(
        '[HDMI_POSE] Canon LV ensure attempt ${i + 1}/$attempts: '
        'enabled=${result.enabled} woke=${result.woke} '
        'holding=${result.holding} ms=$ms corr=$corrId',
      );
      unawaited(
        service.postClientEvent('lv_ensure', {
          'attempt': i + 1,
          'enabled': result.enabled,
          'woke': result.woke,
          'holding': result.holding,
          'ms': ms,
          'corrId': corrId,
        }),
      );
      if (result.enabled || result.holding) {
        return (ok: true, holding: result.holding || result.enabled);
      }
    } catch (e) {
      final ms = DateTime.now().difference(t0).inMilliseconds;
      final info = parseSidecarError(e);
      AppLogger.warning(
        '[HDMI_POSE] Canon LV ensure attempt ${i + 1}/$attempts failed '
        'ms=$ms code=${info.code} eds=${info.edsErrorHex}: $e',
      );
      unawaited(
        service.postClientEvent('lv_ensure_error', {
          'attempt': i + 1,
          'ms': ms,
          'corrId': corrId,
          ...info.toDetail(),
        }),
      );
    }
    if (i < attempts - 1) {
      await Future<void>.delayed(Duration(milliseconds: 350 * (i + 1)));
    }
  }
  AppLogger.warning(
    '[HDMI_POSE] Canon LV ensure exhausted — HDMI may show body status until Q / LV',
  );
  unawaited(service.postClientEvent('lv_ensure_exhausted'));
  return (ok: false, holding: false);
}

/// Tries FotoZen Pi sidecar still capture; returns null to use CameraX/UVC.
///
/// When [resumeLiveView] is false (Classic 1-shot → looks), the Pi skips
/// re-arming LV/keeper after the still — fewer mirror clicks and faster handoff.
///
/// When [preferStripPrintQuality] is true (Classic), request a larger long-edge
/// / higher JPEG quality from the Pi so print/look previews are less soft.
///
/// Writes JPEG bytes to a temp file on native so review/upload have a real
/// path (XFile.fromData left path empty and forced a full in-memory decode of
/// multi‑MP DSLR stills that hung the kiosk).
Future<XFile?> tryCaptureFromSidecar(
  LocalCameraService? service, {
  bool resumeLiveView = true,
  bool preferStripPrintQuality = false,
}) async {
  if (service == null || !service.isConfigured) {
    return null;
  }
  final corrId = service.newCorrId();
  try {
    // Do not hard-skip on a flaky 2s health probe — Android TV often hits
    // SocketException while the Pi is fine; always attempt the still.
    final healthy = await service.isHealthy(corrId: corrId);
    if (!healthy) {
      AppLogger.warning(
        '[HDMI_POSE] Sidecar health soft-fail; attempting capture anyway '
        'corr=$corrId host=${service.baseUrlLabel}',
      );
      unawaited(
        service.postClientEvent('capture_health_soft_fail', {
          'corrId': corrId,
          'host': service.baseUrlLabel,
        }),
      );
    }
    final maxLongEdge = preferStripPrintQuality
        ? kStripCapturedPhotoMaxDimension
        : kSidecarCaptureMaxLongEdge;
    final jpegQuality = preferStripPrintQuality
        ? kStripCapturedPhotoJpegQuality
        : kSidecarCaptureJpegQuality;
    AppLogger.info(
      '[HDMI_POSE] Sidecar still begin resumeLV=$resumeLiveView '
      'stripQ=$preferStripPrintQuality maxEdge=$maxLongEdge q=$jpegQuality '
      'corr=$corrId host=${service.baseUrlLabel}',
    );
    CaptureFlowLog.event(
      'capture.sidecar_begin',
      fields: {
        'resume_lv': resumeLiveView,
        'strip_q': preferStripPrintQuality,
        'max_edge': maxLongEdge,
        'q': jpegQuality,
        'healthy': healthy,
        'corr_id': corrId,
      },
    );
    unawaited(
      service.postClientEvent('capture_begin', {
        'resumeLiveView': resumeLiveView,
        'healthy': healthy,
        'preferStripPrintQuality': preferStripPrintQuality,
        'maxLongEdge': maxLongEdge,
        'jpegQuality': jpegQuality,
        'corrId': corrId,
        'host': service.baseUrlLabel,
      }),
    );
    final t0 = DateTime.now();
    final bytes = await service.capture(
      resumeLiveView: resumeLiveView,
      maxLongEdge: maxLongEdge,
      jpegQuality: jpegQuality,
      corrId: corrId,
    );
    if (bytes.isEmpty) {
      CaptureFlowLog.event(
        'capture.sidecar_empty',
        level: LogLevel.warning,
      );
      unawaited(
        service.postClientEvent('capture_empty', {'corrId': corrId}),
      );
      return null;
    }
    final name = 'fz200d_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final ms = DateTime.now().difference(t0).inMilliseconds;
    AppLogger.info(
      '[HDMI_POSE] Sidecar still ok ($name, ${bytes.length} bytes, '
      'resumeLV=$resumeLiveView, ${ms}ms) corr=$corrId',
    );
    CaptureFlowLog.event(
      'capture.sidecar_ok',
      fields: {
        'bytes': bytes.length,
        'ms': ms,
        'resume_lv': resumeLiveView,
        'corr_id': corrId,
      },
    );
    unawaited(
      service.postClientEvent('capture_ok', {
        'bytes': bytes.length,
        'resumeLiveView': resumeLiveView,
        'ms': ms,
        'corrId': corrId,
      }),
    );
    if (_sidecarTreatAsWeb) {
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
    final info = parseSidecarError(e);
    AppLogger.warning(
      '[HDMI_POSE] Camera sidecar capture failed; falling back '
      'code=${info.code} eds=${info.edsErrorHex} corr=$corrId: $e',
    );
    CaptureFlowLog.event(
      'capture.sidecar_fail',
      fields: {
        'error': '$e',
        'code': info.code,
        'eds_error': info.edsError,
        'corr_id': corrId,
      },
      level: LogLevel.warning,
    );
    unawaited(
      service.postClientEvent('capture_error', {
        'corrId': corrId,
        ...info.toDetail(),
      }),
    );
    return null;
  }
}

/// Persist a DSLR sidecar JPEG for review, baked to match the upright live feed.
///
/// Full-resolution Canon stills (often 20MP+) hang [compute] normalize on
/// Android TV past both the 20s normalize and 45s overall capture budgets —
/// [Future.timeout] cannot cancel an in-flight isolate decode. Sidecar already
/// downscales (~1920 long edge), so a light bake matching live [RotatedBox]
/// turns ([liveFeedSyncedCaptureQuarterTurns]) is safe for strip/print.
///
/// [bakeQuarterTurns] is applied to **sensor/file pixels** (EXIF ignored during
/// decode) — same transform space as the HDMI capture-card preview.
Future<XFile> persistSidecarCaptureStill(
  XFile rawFile, {
  int bakeQuarterTurns = 0,
}) async {
  if (_sidecarTreatAsWeb) {
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
        ? 'Persisting sidecar still (EXIF→pixels if tagged; no live RotatedBox bake)'
        : 'Persisting sidecar still: bake ${turns * 90}° on sensor pixels '
            '(match live RotatedBox; skip full normalize)',
  );
  return ImageHelper.bakeExifAndQuarterTurns(
    source,
    quarterTurns: turns,
    // High quality for EXIF-only bake — avoid crushing Pi ~1920 Canon stills.
    jpegQuality: 95,
  );
}
