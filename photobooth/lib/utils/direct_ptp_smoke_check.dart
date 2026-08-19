import 'package:flutter/foundation.dart' show kDebugMode, visibleForTesting;

import '../services/direct_ptp_camera_service.dart';
import 'logger.dart';

/// Opt-in bring-up check for the direct-PTP DSLR link.
///
/// Off unless explicitly requested:
/// ```
/// --dart-define=CANON_PTP_SMOKE=true
/// ```
///
/// It exists because the camera link has no UI until the native capture screen
/// lands, and "does this app talk to the DSLR at all?" is the one question worth
/// answering before building anything on top of it. It follows the same
/// dart-define lab-override pattern as `CAMERA_SIDECAR_ENABLED`.
///
/// Deliberately does **not** run in normal builds: connecting claims the USB
/// interface and puts the body into remote mode, which would be wrong on a booth
/// still shooting with the device camera.
const String kDirectPtpSmokeDefine =
    String.fromEnvironment('CANON_PTP_SMOKE', defaultValue: '');

bool get directPtpSmokeRequested {
  final v = kDirectPtpSmokeDefine.trim().toLowerCase();
  return v == '1' || v == 'true' || v == 'yes' || v == 'on' || v == 'capture';
}

/// `CANON_PTP_SMOKE=capture` also opens the native capture screen once.
///
/// Separate from the plain connect check because it takes over the display and
/// waits for a human to press the shutter — fine when bringing the screen up,
/// wrong as a side effect of merely checking the link.
///
/// Debug builds only. This fires from `main()`, before any route is built, so it
/// puts a live viewfinder and a running countdown in front of the guest *before*
/// the Terms screen they have not accepted yet. That is a consent problem, not a
/// cosmetic one, so a release build must not be able to reach it even if someone
/// ships the define by accident.
bool get directPtpSmokeCaptureRequested =>
    kDebugMode && kDirectPtpSmokeDefine.trim().toLowerCase() == 'capture';

/// How long the bring-up check waits for a camera to show up on the bus.
const Duration _probeWindow = Duration(seconds: 90);
const Duration _probeInterval = Duration(seconds: 3);

/// Polls until a camera appears, or the window closes.
Future<DirectPtpDevice?> _awaitDevice(
  DirectPtpCameraService camera,
  Duration window,
  Duration interval,
) async {
  final deadline = DateTime.now().add(window);
  var announced = false;
  while (DateTime.now().isBefore(deadline)) {
    final device = await camera.probeDevice();
    if (device != null) return device;
    if (!announced) {
      announced = true;
      AppLogger.info(
        '[PTP_SMOKE] no camera yet — waiting up to ${window.inSeconds}s. '
        'Switch the camera on now if it is off.',
      );
    }
    await Future<void>.delayed(interval);
  }
  return null;
}

/// Probes and connects once, logging what the camera reports. Never throws.
Future<void> runDirectPtpSmokeCheckIfRequested({
  DirectPtpCameraService? service,
  // These three are compile-time constants in production, which leaves the whole
  // body unreachable from a test. Overridable so the bring-up path is covered.
  @visibleForTesting bool? requested,
  @visibleForTesting bool? captureRequested,
  @visibleForTesting Duration? probeWindow,
  @visibleForTesting Duration? probeInterval,
}) async {
  if (!(requested ?? directPtpSmokeRequested)) return;
  final window = probeWindow ?? _probeWindow;
  final interval = probeInterval ?? _probeInterval;
  final camera = service ?? DirectPtpCameraService();
  try {
    AppLogger.info('[PTP_SMOKE] begin');

    final hasHost = await camera.hasUsbHost();
    AppLogger.info('[PTP_SMOKE] usbHost=$hasHost');
    if (!hasHost) {
      AppLogger.warning('[PTP_SMOKE] no USB host support — direct PTP is out');
      return;
    }

    // Wait for the camera rather than sampling once at startup.
    //
    // The body's own auto-power-off drops it off the USB bus within a couple of
    // minutes unless something holds a session open, so a single probe at app
    // start turns bring-up into a race between launching the app and switching
    // the camera on. Polling removes the race: switch the camera on whenever,
    // and this picks it up.
    final device = await _awaitDevice(camera, window, interval);
    if (device == null) {
      AppLogger.warning(
        '[PTP_SMOKE] no PTP camera appeared within ${window.inSeconds}s — '
        'check the cable, that the camera is switched on, that its USB/connection '
        'menu is not in a mass-storage mode, and that auto power off is disabled',
      );
      return;
    }
    AppLogger.info('[PTP_SMOKE] device=$device');

    final status = await camera.connect();
    AppLogger.info('[PTP_SMOKE] connect → $status');
    if (status.isOperational) {
      AppLogger.info(
        '[PTP_SMOKE] OK — ${status.productName ?? 'camera'} in remote mode',
      );
    } else {
      AppLogger.warning('[PTP_SMOKE] not operational: ${status.label} '
          '${status.message ?? ''}');
      return;
    }

    if (!(captureRequested ?? directPtpSmokeCaptureRequested)) return;

    AppLogger.info('[PTP_SMOKE] opening native capture screen');
    final result = await camera.runCaptureSession(
      const DirectPtpCaptureRequest(shotCount: 1),
    );
    AppLogger.info('[PTP_SMOKE] capture → $result');
    for (final shot in result.shots) {
      AppLogger.info(
        '[PTP_SMOKE] shot original=${shot.originalPath} '
        '(${shot.widthPx}x${shot.heightPx}, ${shot.bytes} bytes) '
        'display=${shot.displayPath}',
      );
    }
    if (result.status == DirectPtpCaptureStatus.error) {
      AppLogger.warning(
        '[PTP_SMOKE] capture error ${result.errorCode}: ${result.errorMessage}',
      );
    }
  } catch (e, s) {
    // A bring-up probe must never be able to stop the app from starting.
    AppLogger.warning('[PTP_SMOKE] failed: $e\n$s');
  }
}
