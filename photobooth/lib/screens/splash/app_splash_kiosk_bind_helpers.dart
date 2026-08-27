import '../../models/kiosk_info_model.dart';
import '../../services/kiosk_info_disk_cache.dart';
import '../../services/local_invoice_sequence_hydrate.dart';
import '../../utils/app_strings.dart';
import '../../utils/logger.dart';

/// Outcome of resolving a kiosk code online, with offline disk fallback.
class SplashKioskResolveResult {
  const SplashKioskResolveResult._({
    this.kiosk,
    this.fromCache = false,
    this.errorMessage,
  });

  factory SplashKioskResolveResult.ok(
    KioskInfoModel kiosk, {
    required bool fromCache,
  }) =>
      SplashKioskResolveResult._(kiosk: kiosk, fromCache: fromCache);

  factory SplashKioskResolveResult.fail(String message) =>
      SplashKioskResolveResult._(errorMessage: message);

  final KioskInfoModel? kiosk;
  final bool fromCache;
  final String? errorMessage;

  bool get isOk => kiosk != null && kiosk!.isValid && errorMessage == null;
}

/// Tries live `/api/kiosk/by-code`, persists on success, else loads disk cache
/// for that exact code (device must have bound it online at least once).
Future<SplashKioskResolveResult> resolveSplashKioskByCode({
  required String code,
  required Future<KioskInfoModel?> Function(String code) fetchOnline,
  KioskInfoDiskCache? cache,
}) async {
  final normalized = code.trim().toUpperCase();
  if (normalized.isEmpty) {
    return SplashKioskResolveResult.fail(AppStrings.splashEnterKioskCode);
  }

  final disk = cache ?? KioskInfoDiskCache();
  KioskInfoModel? online;
  try {
    online = await fetchOnline(normalized);
  } catch (e, st) {
    AppLogger.warning(
      'Splash kiosk lookup threw for $normalized',
      error: e,
      stackTrace: st,
    );
    online = null;
  }

  if (online != null && online.isValid) {
    await disk.save(online);
    await hydrateLocalInvoiceSequenceFromKiosk(kiosk: online);
    return SplashKioskResolveResult.ok(online, fromCache: false);
  }

  final cached = await disk.read(normalized);
  if (cached != null && cached.isValid) {
    AppLogger.debug(
      'Splash using cached kiosk $normalized (server unreachable or rejected)',
    );
    await hydrateLocalInvoiceSequenceFromKiosk(kiosk: cached);
    return SplashKioskResolveResult.ok(cached, fromCache: true);
  }

  return SplashKioskResolveResult.fail(
    AppStrings.splashKioskCodeUnavailable,
  );
}
