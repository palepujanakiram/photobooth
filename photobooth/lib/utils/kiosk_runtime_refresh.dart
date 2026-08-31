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

/// Splash bind already loaded settings + Classic flags. Skip Terms Start
/// re-fetch (and overlapping resume force-refresh) inside this window.
const Duration kKioskRuntimeFreshnessTtl = Duration(minutes: 2);

/// Latest `/api/settings` plus Classic flag after a runtime refresh.
class KioskRuntimeRefreshResult {
  const KioskRuntimeRefreshResult({required this.classicPhotosEnabled});

  final bool classicPhotosEnabled;
}

/// True when settings were fetched for [boundKioskKey] within [ttl].
bool isBoundKioskSettingsFresh({
  required DateTime? lastFetchedAt,
  required bool hasSettings,
  String? fetchedKioskKey,
  String? boundKioskKey,
  DateTime Function()? now,
  Duration ttl = kKioskRuntimeFreshnessTtl,
}) {
  if (!hasSettings || lastFetchedAt == null) return false;
  final fetched = (fetchedKioskKey ?? '').trim().toUpperCase();
  final bound = (boundKioskKey ?? '').trim().toUpperCase();
  if (fetched != bound) return false;
  return (now ?? DateTime.now)().difference(lastFetchedAt) < ttl;
}

/// Force-reloads kiosk `/api/settings` (overlay scrub, camera mode, prices).
///
/// Fail-open: timeouts and errors keep the last cached [AppSettingsManager]
/// values so a flaky network does not block Start / splash.
///
/// When [onlyIfStale] is true and settings were fetched within
/// [kKioskRuntimeFreshnessTtl], skips HTTP (Terms Start after splash bind).
Future<void> refreshBoundKioskAppSettings({
  required AppSettingsManager settings,
  Duration timeout = kKioskSettingsRefreshTimeout,
  bool onlyIfStale = false,
}) async {
  if (onlyIfStale &&
      isBoundKioskSettingsFresh(
        lastFetchedAt: settings.lastFetchedAt,
        hasSettings: settings.hasSettings,
        fetchedKioskKey: settings.settingsKioskKey,
        boundKioskKey: await settings.resolveBoundKioskKey(),
      )) {
    return;
  }
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
///
/// Defaults to skipping both GETs when splash just fetched settings.
Future<KioskRuntimeRefreshResult> refreshKioskRuntimeConfig({
  required AppSettingsManager settings,
  required ApiService api,
  required KioskManager kiosk,
  Duration timeout = kKioskSettingsRefreshTimeout,
  bool onlyIfStale = true,
}) async {
  if (onlyIfStale &&
      isBoundKioskSettingsFresh(
        lastFetchedAt: settings.lastFetchedAt,
        hasSettings: settings.hasSettings,
        fetchedKioskKey: settings.settingsKioskKey,
        boundKioskKey: await kiosk.getKioskCode(),
      )) {
    return KioskRuntimeRefreshResult(
      classicPhotosEnabled: await kiosk.isClassicPhotosEnabled(),
    );
  }
  final classicFuture = syncClassicPhotosEnabled(api: api, kiosk: kiosk);
  final settingsFuture = refreshBoundKioskAppSettings(
    settings: settings,
    timeout: timeout,
    onlyIfStale: false,
  );
  await settingsFuture;
  return KioskRuntimeRefreshResult(
    classicPhotosEnabled: await classicFuture,
  );
}
