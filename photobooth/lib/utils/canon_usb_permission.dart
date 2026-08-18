import 'package:flutter/foundation.dart';

import '../models/app_settings_model.dart';
import 'camera_sidecar_config.dart';
import 'canon_sidecar_status_channel.dart';

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

/// True when the native sidecar is waiting for USB permission.
Future<bool> canonSidecarAwaitingUsbPermission() async {
  if (defaultTargetPlatform != TargetPlatform.android) return false;
  final state = await CanonSidecarStatusChannel.getState();
  return state == 'waiting_usb';
}
