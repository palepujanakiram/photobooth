import 'package:flutter/foundation.dart' show visibleForTesting;

import '../models/app_settings_model.dart';
import '../services/direct_ptp_camera_service.dart';
import 'camera_source_config.dart';
import 'logger.dart';

/// Aligns the native Canon stack with ZenAI / dart-define capture mode.
///
/// Safe to call on every settings fetch; no-ops on web / non-Android.
Future<void> syncCanonCameraStackForSettings(
  AppSettingsModel? settings, {
  @visibleForTesting DirectPtpCameraService? camera,
}) async {
  try {
    final preferPtp = usesDirectPtpCamera(settings: settings);
    final result = await (camera ?? DirectPtpCameraService()).setPreferredStack(
      preferPtp: preferPtp,
    );
    AppLogger.info(
      'Canon stack sync preferPtp=$preferPtp '
      'stack=${result['stack']} changed=${result['changed']}',
    );
  } catch (e, st) {
    AppLogger.warning(
      'Canon stack sync failed',
      error: e,
      stackTrace: st,
    );
  }
}
