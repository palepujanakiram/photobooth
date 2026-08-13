import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;

import '../../services/file_helper.dart';
import '../../services/local_camera_service.dart';
import '../../utils/capture_flow_log.dart';
import '../../utils/image_helper.dart';
import '../../utils/logger.dart';

/// When true, sidecar helpers take the web (in-memory XFile) branches.
@visibleForTesting
bool debugSidecarHelpersForceWeb = false;

bool get _sidecarTreatAsWeb => kIsWeb || debugSidecarHelpersForceWeb;

/// Still JPEGs below this luma look “almost black” vs EVF preview.
const double kSidecarStillDarkLuma = 48;

/// Prefer the live-view JPEG when it is at least this much brighter.
const double kSidecarLiveBrighterDelta = 24;

/// Canon EVF is gain-boosted; the shutter JPEG uses still AE and is often
/// several stops darker indoors. Pose should keep the frame the guest saw.
bool shouldPreferLiveViewJpeg({
  required double? stillLuma,
  required double? liveLuma,
}) {
  if (stillLuma == null || liveLuma == null) return false;
  return stillLuma < kSidecarStillDarkLuma &&
      liveLuma >= stillLuma + kSidecarLiveBrighterDelta;
}

Future<Uint8List> pickSidecarCaptureJpeg({
  required Uint8List stillJpeg,
  Uint8List? liveJpeg,
  Future<double?> Function(Uint8List bytes)? meanLuma,
}) async {
  final live = liveJpeg;
  if (live == null ||
      live.isEmpty ||
      !sidecarHttpBodyLooksLikeJpeg(live)) {
    return stillJpeg;
  }
  final lumaOf = meanLuma ?? meanJpegLuma;
  final stillLuma = await lumaOf(stillJpeg);
  final liveLuma = await lumaOf(live);
  if (!shouldPreferLiveViewJpeg(stillLuma: stillLuma, liveLuma: liveLuma)) {
    return stillJpeg;
  }
  AppLogger.info(
    '[HDMI_POSE] Still too dark (luma=${stillLuma!.toStringAsFixed(1)}) '
    'vs live (${liveLuma!.toStringAsFixed(1)}); using live-view JPEG',
  );
  return live;
}

/// True when [cameraId] is a Pi gphoto2 / FZ200D still.
bool isSidecarCameraId(String? cameraId) {
  final id = cameraId?.trim() ?? '';
  return id.startsWith('sidecar:');
}

/// Native sidecar states that cannot listen on `127.0.0.1:8791`.
///
/// `unsupported_abi` is x86 / non-ARM. ARM32 and ARM64 Android both ship a
/// matching EDSDK sidecar. `crashed` / `max_restarts` mean the process exited.
bool shouldTreatSidecarNativeStateAsDead(String state) {
  return state == 'unsupported_abi' ||
      state == 'crashed' ||
      state == 'max_restarts';
}

/// Probes native sidecar lifecycle; marks the Dart client unused when dead.
///
/// Returns false when pose must open HDMI/UVC instead of polling localhost.
Future<bool> sidecarNativeProcessCanServeHttp(
  LocalCameraService? service, {
  required Future<String> Function() queryNativeState,
  Duration nativeStateTimeout = const Duration(seconds: 1),
}) async {
  if (service == null || !service.isConfigured) return false;
  String state;
  try {
    state = await queryNativeState().timeout(
      nativeStateTimeout,
      onTimeout: () => 'idle',
    );
  } catch (_) {
    state = 'idle';
  }
  if (shouldTreatSidecarNativeStateAsDead(state)) {
    service.markRuntimeUnavailable();
    return false;
  }
  if (state == 'running') return true;
  final listening = await service.isListening();
  if (listening) return true;
  service.markRuntimeUnavailable();
  return false;
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
    try {
      final result = await service.ensureLiveView();
      AppLogger.info(
        '[HDMI_POSE] Canon LV ensure attempt ${i + 1}/$attempts: '
        'enabled=${result.enabled} woke=${result.woke} '
        'holding=${result.holding}',
      );
      unawaited(
        service.postClientEvent('lv_ensure', {
          'attempt': i + 1,
          'enabled': result.enabled,
          'woke': result.woke,
          'holding': result.holding,
        }),
      );
      if (result.enabled || result.holding) {
        return (ok: true, holding: result.holding || result.enabled);
      }
    } catch (e) {
      AppLogger.warning(
        '[HDMI_POSE] Canon LV ensure attempt ${i + 1}/$attempts failed: $e',
      );
      unawaited(
        service.postClientEvent('lv_ensure_error', {
          'attempt': i + 1,
          'error': '$e',
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
  try {
    // Do not hard-skip on a flaky 2s health probe — Android TV often hits
    // SocketException while the Pi is fine; always attempt the still.
    final healthy = await service.isHealthy();
    if (!healthy) {
      AppLogger.warning(
        '[HDMI_POSE] Sidecar health soft-fail; attempting capture anyway',
      );
      unawaited(service.postClientEvent('capture_health_soft_fail'));
    }
    final maxLongEdge = preferStripPrintQuality
        ? kStripCapturedPhotoMaxDimension
        : kSidecarCaptureMaxLongEdge;
    final jpegQuality = preferStripPrintQuality
        ? kStripCapturedPhotoJpegQuality
        : kSidecarCaptureJpegQuality;
    AppLogger.info(
      '[HDMI_POSE] Sidecar still begin resumeLV=$resumeLiveView '
      'stripQ=$preferStripPrintQuality maxEdge=$maxLongEdge q=$jpegQuality',
    );
    CaptureFlowLog.event(
      'capture.sidecar_begin',
      fields: {
        'resume_lv': resumeLiveView,
        'strip_q': preferStripPrintQuality,
        'max_edge': maxLongEdge,
        'q': jpegQuality,
        'healthy': healthy,
      },
    );
    unawaited(
      service.postClientEvent('capture_begin', {
        'resumeLiveView': resumeLiveView,
        'healthy': healthy,
        'preferStripPrintQuality': preferStripPrintQuality,
        'maxLongEdge': maxLongEdge,
        'jpegQuality': jpegQuality,
      }),
    );
    Uint8List? liveJpeg;
    try {
      liveJpeg = await service.fetchPreviewJpeg(
        timeout: const Duration(seconds: 2),
      );
    } catch (e) {
      AppLogger.warning('[HDMI_POSE] Sidecar live freeze before capture: $e');
    }
    try {
      await service.prepareStill(timeout: const Duration(seconds: 8));
    } catch (e) {
      AppLogger.warning(
        '[HDMI_POSE] Sidecar prepare-still before capture: $e',
      );
    }
    final t0 = DateTime.now();
    var bytes = await service.capture(
      resumeLiveView: resumeLiveView,
      maxLongEdge: maxLongEdge,
      jpegQuality: jpegQuality,
    );
    if (bytes.isEmpty) {
      CaptureFlowLog.event(
        'capture.sidecar_empty',
        level: LogLevel.warning,
      );
      return null;
    }
    bytes = await pickSidecarCaptureJpeg(
      stillJpeg: bytes,
      liveJpeg: liveJpeg,
    );
    final name = 'fz200d_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final ms = DateTime.now().difference(t0).inMilliseconds;
    AppLogger.info(
      '[HDMI_POSE] Sidecar still ok ($name, ${bytes.length} bytes, '
      'resumeLV=$resumeLiveView, ${ms}ms)',
    );
    CaptureFlowLog.event(
      'capture.sidecar_ok',
      fields: {'bytes': bytes.length, 'ms': ms, 'resume_lv': resumeLiveView},
    );
    unawaited(
      service.postClientEvent('capture_ok', {
        'bytes': bytes.length,
        'resumeLiveView': resumeLiveView,
        'ms': ms,
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
    AppLogger.warning('[HDMI_POSE] Camera sidecar capture failed; falling back: $e');
    CaptureFlowLog.event(
      'capture.sidecar_fail',
      fields: {'error': '$e'},
      level: LogLevel.warning,
    );
    unawaited(
      service.postClientEvent('capture_error', {'error': '$e'}),
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
  final source = await _materializeSidecarStillFile(rawFile);
  final sized = await ImageHelper.downscaleJpegToMaxLongEdge(
    source,
    maxLongEdge: kSidecarCaptureMaxLongEdge,
    jpegQuality: 95,
  );
  final turns = ((bakeQuarterTurns % 4) + 4) % 4;
  AppLogger.info(
    turns == 0
        ? 'Persisting sidecar still (EXIF→pixels if tagged; no live RotatedBox bake)'
        : 'Persisting sidecar still: bake ${turns * 90}° on sensor pixels '
            '(match live RotatedBox; skip full normalize)',
  );
  return ImageHelper.bakeExifAndQuarterTurns(
    sized,
    quarterTurns: turns,
    // High quality for EXIF-only bake — avoid crushing Pi ~1920 Canon stills.
    jpegQuality: 95,
  );
}

Future<XFile> _materializeSidecarStillFile(XFile rawFile) async {
  final bytes = await rawFile.readAsBytes();
  if (bytes.isEmpty) {
    throw Exception('Sidecar capture is empty');
  }
  if (!sidecarHttpBodyLooksLikeJpeg(bytes)) {
    throw Exception('Sidecar capture is not a JPEG still');
  }
  if (rawFile.path.isNotEmpty) return rawFile;
  final tempDir = await FileHelper.getTempDirectoryPath();
  final dir = '$tempDir/sidecar';
  await FileHelper.ensureDirectory(dir);
  final path = '$dir/fz200d_${DateTime.now().millisecondsSinceEpoch}.jpg';
  final file = FileHelper.createFile(path);
  await (file as dynamic).writeAsBytes(bytes, flush: true);
  return XFile(path, mimeType: 'image/jpeg');
}
