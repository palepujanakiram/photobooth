import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/app_settings_model.dart';
import '../services/direct_ptp_camera_service.dart';
import '../services/local_camera_service.dart';
import 'camera_sidecar_config.dart';
import 'camera_source_config.dart';
import 'canon_sidecar_status_channel.dart';
import 'canon_stack_sync.dart';

/// True for on-device EDSDK USB booths (not Pi/LAN).
bool isDirectCanonSidecarBooth(AppSettingsModel? settings) {
  final cfg = resolveCameraSidecarConfig(settings);
  return cfg.isDirectConnection && cfg.isConfigured;
}

/// True when the native Kotlin PTP stack owns the DSLR (not EDSDK sidecar).
bool isDirectPtpBooth(AppSettingsModel? settings) =>
    usesDirectPtpCamera(settings: settings);

/// True for any on-device Canon USB booth (EDSDK sidecar or native PTP).
bool isOnDeviceCanonUsbBooth(AppSettingsModel? settings) =>
    isDirectCanonSidecarBooth(settings) || isDirectPtpBooth(settings);

/// Requests Android USB access for a direct Canon EDSDK booth.
///
/// Pi/LAN sidecars do not need on-device USB permission. Safe no-op on
/// non-Android and when direct USB is not configured.
Future<bool> ensureCanonUsbPermissionForDirectSidecar({
  AppSettingsModel? settings,
  CameraSidecarConfig? config,
}) async {
  if (defaultTargetPlatform != TargetPlatform.android) return true;
  final cfg = config ?? resolveCameraSidecarConfig(settings);
  if (!cfg.isDirectConnection || !cfg.isConfigured) return true;
  if (!await CanonSidecarStatusChannel.isCameraPresent()) return true;
  if (await CanonSidecarStatusChannel.hasUsbPermission()) return true;
  return CanonSidecarStatusChannel.requestUsbPermissionIfNeeded();
}

/// Poll localhost EDSDK while the guest is on Terms (after USB allow).
Future<bool> warmDirectSidecarAfterUsbGrant({
  AppSettingsModel? settings,
  CameraSidecarConfig? config,
  Duration timeout = const Duration(seconds: 20),
  Duration pollInterval = const Duration(milliseconds: 500),
  http.Client? client,
}) async {
  if (defaultTargetPlatform != TargetPlatform.android) return false;
  final cfg = config ?? resolveCameraSidecarConfig(settings);
  if (!cfg.isDirectConnection || !cfg.isConfigured) return false;
  if (!await CanonSidecarStatusChannel.isCameraPresent()) return false;

  final service = LocalCameraService(config: cfg, client: client);
  try {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await service.isListening()) return true;
      final state = await CanonSidecarStatusChannel.getState().timeout(
        const Duration(milliseconds: 800),
        onTimeout: () => 'idle',
      );
      if (state == 'waiting_usb') {
        await CanonSidecarStatusChannel.requestUsbPermissionIfNeeded();
      }
      if (state == 'running' && await service.isHealthy()) return true;
      await Future<void>.delayed(pollInterval);
    }
    return false;
  } finally {
    service.dispose();
  }
}

/// First action on Terms for direct Canon booths: USB allow dialog, then warm-up.
Future<bool> primeCanonUsbOnTermsLaunch({
  AppSettingsModel? settings,
  http.Client? client,
}) async {
  if (!isDirectCanonSidecarBooth(settings)) return true;
  if (!await isDirectCanonHardwareAvailable(settings: settings)) return true;
  final granted = await ensureCanonUsbPermissionForDirectSidecar(
    settings: settings,
  );
  await warmDirectSidecarAfterUsbGrant(settings: settings, client: client);
  return granted;
}

/// Requests USB access for a direct-PTP booth and opens the PTP session when allowed.
Future<bool> ensureDirectPtpUsbOnTerms({
  AppSettingsModel? settings,
  DirectPtpCameraService? camera,
}) async {
  if (defaultTargetPlatform != TargetPlatform.android) return true;
  if (!isDirectPtpBooth(settings)) return true;

  final service = camera ?? DirectPtpCameraService();
  if (!service.isSupported) return true;
  if (!await service.hasUsbHost()) return false;

  final device = await service.probeDevice();
  if (device == null) return false;
  if (device.hasPermission) return true;

  final status = await service.connect();
  return status.state != DirectPtpState.permissionDenied;
}

/// True when native PTP has no camera on the bus (skip Terms warm-up).
bool _directPtpStateMeansNoBody(DirectPtpState state) =>
    state == DirectPtpState.noDevice ||
    state == DirectPtpState.noUsbHost ||
    state == DirectPtpState.detached;

/// Poll native PTP while the guest is on Terms (after USB allow).
///
/// The 20 s loop is only for a body that is already on USB but still opening a
/// session. No Canon on the bus means no session is coming — same early-out as
/// [warmDirectSidecarAfterUsbGrant].
Future<bool> warmDirectPtpOnTerms({
  AppSettingsModel? settings,
  Duration timeout = const Duration(seconds: 20),
  Duration pollInterval = const Duration(milliseconds: 500),
  DirectPtpCameraService? camera,
}) async {
  if (defaultTargetPlatform != TargetPlatform.android) return false;
  if (!isDirectPtpBooth(settings)) return false;

  final service = camera ?? DirectPtpCameraService();
  final initial = await service.status();
  if (initial.state.isOperational) return true;
  // Skip only when the USB list and the session both say no body. A connected
  // Canon (including one still opening a session) always continues into the loop.
  if (await service.probeDevice() == null &&
      _directPtpStateMeansNoBody(initial.state)) {
    return false;
  }

  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final status = await service.status();
    if (status.state.isOperational) return true;

    final device = await service.probeDevice();
    if (device != null) {
      if (device.hasPermission) {
        final connectStatus = await service.connect();
        if (connectStatus.state.isOperational) return true;
      } else {
        final connectStatus = await service.connect();
        if (connectStatus.state.isOperational) return true;
        if (connectStatus.state == DirectPtpState.permissionDenied) {
          return false;
        }
      }
    }
    await Future<void>.delayed(pollInterval);
  }
  return false;
}

/// True when direct PTP is connected or USB permission is already held.
Future<bool> isDirectPtpReadyForTerms({
  AppSettingsModel? settings,
  DirectPtpCameraService? camera,
}) async {
  if (defaultTargetPlatform != TargetPlatform.android) return false;
  if (!isDirectPtpBooth(settings)) return false;

  final service = camera ?? DirectPtpCameraService();
  final status = await service.status();
  if (status.state.isOperational) return true;

  final device = await service.probeDevice();
  return device != null && device.hasPermission;
}

/// First action on Terms for direct-PTP booths: USB allow dialog, then warm-up.
Future<bool> primeDirectPtpOnTermsLaunch({
  AppSettingsModel? settings,
  DirectPtpCameraService? camera,
}) async {
  if (!isDirectPtpBooth(settings)) return true;
  // Connected Canon (open session or body on USB) still gets USB grant + warm-up.
  // Only phones/tablets with no DSLR skip the 20 s poll.
  final sessionReady =
      await isDirectPtpReadyForTerms(settings: settings, camera: camera);
  final bodyOnUsb =
      await isDirectPtpHardwareAvailable(settings: settings, camera: camera);
  if (!sessionReady && !bodyOnUsb) return true;
  final granted = await ensureDirectPtpUsbOnTerms(
    settings: settings,
    camera: camera,
  );
  await warmDirectPtpOnTerms(settings: settings, camera: camera);
  return granted;
}

/// True when a Canon DSLR is on USB for the on-device EDSDK sidecar.
///
/// Direct mode defaults to localhost `:8791` even on phones with no body.
/// POSE / Terms must not wait for USB permission or EVF unless this is true.
Future<bool> isDirectCanonHardwareAvailable({
  AppSettingsModel? settings,
}) async {
  if (defaultTargetPlatform != TargetPlatform.android) return false;
  if (settings != null && !isDirectCanonSidecarBooth(settings)) {
    return false;
  }
  return CanonSidecarStatusChannel.isCameraPresent();
}

/// True when a Canon body is attached over USB (native PTP capture may proceed).
///
/// Used to fall back to CameraX/UVC when `cameraConnectionMode=direct_ptp` but no
/// DSLR is plugged in (dev tablets, phones, mis-cabled kiosks).
Future<bool> isDirectPtpHardwareAvailable({
  AppSettingsModel? settings,
  DirectPtpCameraService? camera,
}) async {
  if (defaultTargetPlatform != TargetPlatform.android) return false;
  if (!isDirectPtpBooth(settings)) return false;

  final service = camera ?? DirectPtpCameraService();
  if (!service.isSupported) return false;
  if (!await service.hasUsbHost()) return false;

  final device = await service.probeDevice();
  return device != null;
}

/// Syncs PTP vs EDSDK, clears faulted sessions, and connects before POSE capture.
///
/// The native capture Activity used to be the first connect attempt; a half-open
/// session from Terms priming or a waking body then surfaced as connect_failed
/// until the guest tapped Try again.
Future<bool> prepareDirectPtpPoseSession({
  AppSettingsModel? settings,
  DirectPtpCameraService? camera,
  Duration timeout = const Duration(seconds: 20),
  Duration pollInterval = const Duration(milliseconds: 500),
}) async {
  if (defaultTargetPlatform != TargetPlatform.android) return false;
  if (!isDirectPtpBooth(settings)) return true;

  final service = camera ?? DirectPtpCameraService();
  if (!service.isSupported) return false;

  await syncCanonCameraStackForSettings(settings);

  var status = await service.status();
  if (status.state.isFault) {
    await service.disconnect();
    status = await service.status();
  }
  if (status.state.isOperational) return true;

  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    status = await service.connect();
    if (status.state.isOperational) return true;
    if (status.state == DirectPtpState.permissionDenied) return false;
    if (status.state.isFault) {
      await service.disconnect();
    }
    await Future<void>.delayed(pollInterval);
  }
  return false;
}

/// True when the native sidecar is waiting for USB permission.
Future<bool> canonSidecarAwaitingUsbPermission() async {
  if (defaultTargetPlatform != TargetPlatform.android) return false;
  final state = await CanonSidecarStatusChannel.getState();
  return state == 'waiting_usb';
}

/// True when Terms should not name the Canon USB allow dialog.
///
/// That includes a grant already held from an earlier guest, and a configured
/// Canon booth with no body on USB — no system dialog is coming, so the
/// generic "Getting the camera ready…" copy is the honest one.
Future<bool> isOnDeviceCanonUsbPermissionHeld({
  AppSettingsModel? settings,
  DirectPtpCameraService? camera,
}) async {
  if (defaultTargetPlatform != TargetPlatform.android) return false;
  if (isDirectPtpBooth(settings)) {
    // No body on USB means no allow dialog is coming — same as EDSDK sidecar.
    if (!await isDirectPtpHardwareAvailable(
      settings: settings,
      camera: camera,
    )) {
      return true;
    }
    return isDirectPtpReadyForTerms(settings: settings, camera: camera);
  }
  if (!isDirectCanonSidecarBooth(settings)) return false;
  // No body on USB means no allow dialog is coming — treat the grant as held so
  // Terms keeps the generic copy instead of naming a camera that is not there.
  if (!await isDirectCanonHardwareAvailable(settings: settings)) return true;
  return CanonSidecarStatusChannel.hasUsbPermission();
}

/// True when a booth primed on an earlier guest is still camera-ready.
///
/// Deliberately short-deadlined: this runs on the Terms fast path, so a body
/// that was unplugged between guests must fail quickly and fall through to a
/// full priming pass rather than stall the screen.
Future<bool> isOnDeviceCanonBoothStillReady({
  AppSettingsModel? settings,
  DirectPtpCameraService? camera,
  http.Client? client,
  Duration sidecarTimeout = const Duration(seconds: 2),
}) async {
  if (defaultTargetPlatform != TargetPlatform.android) return false;
  if (isDirectPtpBooth(settings)) {
    return isDirectPtpReadyForTerms(settings: settings, camera: camera);
  }
  if (!isDirectCanonSidecarBooth(settings)) return false;
  return warmDirectSidecarAfterUsbGrant(
    settings: settings,
    client: client,
    timeout: sidecarTimeout,
  );
}
