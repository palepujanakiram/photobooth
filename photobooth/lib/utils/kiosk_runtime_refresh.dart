import 'dart:async';

import '../services/api_service.dart';
import '../services/app_settings_manager.dart';
import '../services/kiosk_manager.dart';
import 'app_strings.dart';
import 'classic_photos_enabled_sync.dart';
import 'logger.dart';

/// Bound for `/api/settings` on splash bind and Terms Start.
///
/// Matches splash's existing kiosk-code / settings wait so a hung API does not
/// freeze the guest CTA.
const Duration kKioskSettingsRefreshTimeout = Duration(seconds: 12);

/// Latest `/api/settings` plus Classic flag after a runtime refresh.
class KioskRuntimeRefreshResult {
  const KioskRuntimeRefreshResult({required this.classicPhotosEnabled});

  final bool classicPhotosEnabled;
}

/// Force-reloads kiosk `/api/settings` (overlay scrub, camera mode, prices).
///
/// Fail-open: timeouts and errors keep the last cached [AppSettingsManager]
/// values so a flaky network does not block Start / splash.
Future<void> refreshBoundKioskAppSettings({
  required AppSettingsManager settings,
  Duration timeout = kKioskSettingsRefreshTimeout,
}) async {
  try {
    await settings.fetchSettings(forceRefresh: true).timeout(timeout);
  } on TimeoutException catch (e, st) {
    AppLogger.warning(
      AppStrings.kioskSettingsRefreshTimedOut,
      error: e,
      stackTrace: st,
    );
  } catch (e, st) {
    AppLogger.warning(
      AppStrings.kioskSettingsRefreshFailed,
      error: e,
      stackTrace: st,
    );
  }
}

/// Settings + kiosk Classic flag in parallel (Terms "Start Your Experience").
Future<KioskRuntimeRefreshResult> refreshKioskRuntimeConfig({
  required AppSettingsManager settings,
  required ApiService api,
  required KioskManager kiosk,
  Duration timeout = kKioskSettingsRefreshTimeout,
}) async {
  final classicFuture = syncClassicPhotosEnabled(api: api, kiosk: kiosk);
  final settingsFuture = refreshBoundKioskAppSettings(
    settings: settings,
    timeout: timeout,
  );
  await settingsFuture;
  return KioskRuntimeRefreshResult(
    classicPhotosEnabled: await classicFuture,
  );
}
