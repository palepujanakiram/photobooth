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
  return v == '1' || v == 'true' || v == 'yes' || v == 'on';
}

/// Probes and connects once, logging what the camera reports. Never throws.
Future<void> runDirectPtpSmokeCheckIfRequested({
  DirectPtpCameraService? service,
}) async {
  if (!directPtpSmokeRequested) return;
  final camera = service ?? DirectPtpCameraService();
  try {
    AppLogger.info('[PTP_SMOKE] begin');

    final hasHost = await camera.hasUsbHost();
    AppLogger.info('[PTP_SMOKE] usbHost=$hasHost');
    if (!hasHost) {
      AppLogger.warning('[PTP_SMOKE] no USB host support — direct PTP is out');
      return;
    }

    final device = await camera.probeDevice();
    AppLogger.info('[PTP_SMOKE] device=${device ?? 'none'}');
    if (device == null) {
      AppLogger.warning(
        '[PTP_SMOKE] no PTP camera on the bus — check the cable, and that the '
        "camera's USB/connection menu is not in a mass-storage mode",
      );
      return;
    }

    final status = await camera.connect();
    AppLogger.info('[PTP_SMOKE] connect → $status');
    if (status.isOperational) {
      AppLogger.info(
        '[PTP_SMOKE] OK — ${status.productName ?? 'camera'} in remote mode',
      );
    } else {
      AppLogger.warning('[PTP_SMOKE] not operational: ${status.label} '
          '${status.message ?? ''}');
    }
  } catch (e, s) {
    // A bring-up probe must never be able to stop the app from starting.
    AppLogger.warning('[PTP_SMOKE] failed: $e\n$s');
  }
}
