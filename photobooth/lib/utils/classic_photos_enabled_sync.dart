import '../models/kiosk_info_model.dart';
import '../services/api_service.dart';
import '../services/kiosk_manager.dart';
import 'logger.dart';

/// Re-fetches kiosk metadata and updates the Classic photos flag.
///
/// Splash bind caches [KioskManager.setClassicPhotosEnabled] in prefs + memory.
/// Long-running booths that never re-enter splash keep a stale `false` after
/// Classic is turned on in admin — call this before the experience choice gate.
Future<bool> syncClassicPhotosEnabled({
  required ApiService api,
  required KioskManager kiosk,
}) async {
  final code = await kiosk.getKioskCode();
  if (code == null || code.isEmpty) {
    return kiosk.isClassicPhotosEnabled();
  }
  try {
    final KioskInfoModel? info = await api.fetchKioskByCode(code);
    if (info != null) {
      await kiosk.setClassicPhotosEnabled(info.classicPhotosEnabled);
      await kiosk.setClassicShotModes(info.classicShotModes);
      await kiosk.setOperatingModeOffline(info.isOperatingModeOffline);
      AppLogger.debug(
        'Classic photos enabled synced from API: ${info.classicPhotosEnabled} '
        'shotModes=${info.classicShotModes} '
        'operatingMode=${info.operatingMode} (kiosk=$code)',
      );
      return info.classicPhotosEnabled;
    }
  } catch (e) {
    AppLogger.warning('Classic photos sync failed; using cache: $e');
  }
  return kiosk.isClassicPhotosEnabled();
}
