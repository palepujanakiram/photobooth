import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/app_settings_model.dart';
import '../services/local_camera_service.dart';
import 'camera_sidecar_config.dart';
import 'canon_sidecar_status_channel.dart';

/// True for on-device EDSDK USB booths (not Pi/LAN).
bool isDirectCanonSidecarBooth(AppSettingsModel? settings) {
  final cfg = resolveCameraSidecarConfig(settings);
  return cfg.isDirectConnection && cfg.isConfigured;
}

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
  final granted = await ensureCanonUsbPermissionForDirectSidecar(
    settings: settings,
  );
  await warmDirectSidecarAfterUsbGrant(settings: settings, client: client);
  return granted;
}

/// True when the native sidecar is waiting for USB permission.
Future<bool> canonSidecarAwaitingUsbPermission() async {
  if (defaultTargetPlatform != TargetPlatform.android) return false;
  final state = await CanonSidecarStatusChannel.getState();
  return state == 'waiting_usb';
}
