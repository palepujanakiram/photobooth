import 'package:flutter/foundation.dart';
import '../models/app_settings_model.dart';
import '../utils/app_runtime_config.dart';
import '../utils/canon_stack_sync.dart';
import '../utils/constants.dart';
import '../utils/logger.dart';
import 'alice_inspector.dart';
import 'api_service.dart';
import 'app_settings_cache_codec.dart';
import 'catalog_disk_cache.dart';
import 'kiosk_manager.dart';
import 'offline_operator_pin_store.dart';

class AppSettingsManager extends ChangeNotifier {
  ApiService _apiService;
  final Future<String?> Function() _resolveKioskCode;

  AppSettingsManager({
    ApiService? apiService,
    @visibleForTesting Future<String?> Function()? resolveKioskCode,
    CatalogDiskCache? diskCache,
  })  : _apiService = apiService ?? ApiService(),
        _resolveKioskCode =
            resolveKioskCode ?? (() => KioskManager().getKioskCode()),
        _diskCache = diskCache ?? CatalogDiskCache();

  final CatalogDiskCache _diskCache;

  AppSettingsModel? _settings;
  bool _isLoading = false;
  String? _errorMessage;
  DateTime? _lastFetchedAt;
  Future<void>? _inflightFetch;

  /// Kiosk code (uppercased) used for the last successful settings fetch.
  /// Empty string means account-default settings (no kiosk query).
  String? _settingsKioskKey;

  AppSettingsModel? get settings => _settings;
  bool get hasSettings => _settings != null;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  DateTime? get lastFetchedAt => _lastFetchedAt;

  /// Uppercased kiosk code of the last successful network settings fetch.
  String? get settingsKioskKey => _settingsKioskKey;

  /// Currently bound kiosk code (uppercased), or empty if none.
  Future<String> resolveBoundKioskKey() => _currentKioskKey();

  /// Recreate the HTTP client after splash Stage/Live host change.
  void rebindApiService({ApiService? apiService}) {
    _apiService = apiService ?? ApiService();
  }

  /// True when account settings collect UPI before AI generation.
  bool get collectPaymentBeforeGeneration =>
      _settings?.paymentCollectionTiming ==
      AppConstants.kPaymentCollectionBeforeGeneration;

  /// `/api/settings` → `parallelImageCount`, clamped. Drives POST vs parallel SSE in [ApiService.generateImages].
  int resolveParallelImageCount() {
    final raw = _settings?.parallelImageCount;
    final base = (raw != null && raw > 0)
        ? raw
        : AppConstants.kAiParallelGenerationCount;
    return base.clamp(1, AppConstants.kMaxParallelImageSlots);
  }

  Future<String> _currentKioskKey() async {
    final code = (await _resolveKioskCode())?.trim().toUpperCase() ?? '';
    return code;
  }

  /// Last persisted settings, no HTTP.
  ///
  /// Launch used to GET account-default `/api/settings` before splash bound a
  /// kiosk; that payload was replaced by `?kiosk=` on bind. Splash still
  /// force-refreshes with the bound code.
  Future<void> hydrateFromCache() async {
    final kioskKey = await _currentKioskKey();
    await _hydrateFromDisk(kioskKey);
    if (_settings != null) {
      applyFlutterImageCacheLimits();
      // ignore: unawaited_futures
      syncCanonCameraStackForSettings(_settings);
    }
    notifyListeners();
  }

  /// App resume: use disk/memory only when no kiosk is bound.
  ///
  /// A USB/camera permission pause must not GET unscoped `/api/settings`;
  /// splash bind still force-refreshes `?kiosk=`.
  Future<void> refreshOnAppResume() async {
    final kioskKey = await _currentKioskKey();
    if (kioskKey.isEmpty) {
      await hydrateFromCache();
      return;
    }
    await fetchSettings();
  }

  Future<void> fetchSettings({bool forceRefresh = false}) async {
    final kioskKey = await _currentKioskKey();
    final kioskChanged =
        _settings != null && _settingsKioskKey != null && _settingsKioskKey != kioskKey;

    if (!forceRefresh && !kioskChanged && _settings == null) {
      await _hydrateFromDisk(kioskKey);
    }

    // Startup often loads settings before splash binds a kiosk. When the bound
    // kiosk changes, ignore the account-default cache so guest prices refresh.
    // Disk hydrate (no [_lastFetchedAt]) is enough until splash force-refresh.
    if (!forceRefresh && !kioskChanged && _settings != null) {
      // Keep [AppRuntimeConfig] in sync when callers reuse cached settings.
      AppRuntimeConfig.instance.applyFromSettings(_settings);
      AliceInspector.syncWithRuntimeConfig();
      return;
    }

    // Reuse an in-flight GET even for forceRefresh so splash bind, app resume
    // (USB/camera permission dialogs), and Terms Start do not stack.
    // A kiosk change still starts a new request for the bound code.
    if (!kioskChanged && _inflightFetch != null) {
      return _inflightFetch!;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final f = () async {
      try {
        final response = await _apiService.getAppSettings();
        _settings = response;
        _settingsKioskKey = kioskKey;
        _lastFetchedAt = DateTime.now();
        _errorMessage = null;
        AppRuntimeConfig.instance.applyFromSettings(_settings);
        AliceInspector.syncWithRuntimeConfig();
        await _persistToDisk(kioskKey);
        await _syncOfflineCashPins();
        applyFlutterImageCacheLimits();
        // Fire-and-forget: stop/start EDSDK vs PTP to match ZenAI mode.
        // ignore: unawaited_futures
        syncCanonCameraStackForSettings(_settings);
      } catch (e, st) {
        _errorMessage = e.toString();
        AppLogger.error(
          'Failed to fetch app settings',
          error: e,
          stackTrace: st,
        );
        if (_settings == null) {
          await _hydrateFromDisk(kioskKey);
        }
      } finally {
        _isLoading = false;
        notifyListeners();
      }
    }();

    _inflightFetch = f;
    try {
      await f;
    } finally {
      if (identical(_inflightFetch, f)) {
        _inflightFetch = null;
      }
    }
  }

  String _diskKey(String kioskKey) {
    final safe = kioskKey.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    return 'settings_${safe.isEmpty ? 'default' : safe}';
  }

  Future<void> _hydrateFromDisk(String kioskKey) async {
    if (_settings != null) return;
    final parsed =
        appSettingsFromCacheJson(await _diskCache.readJson(_diskKey(kioskKey)));
    if (parsed == null) return;
    _settings = parsed;
    _settingsKioskKey = kioskKey;
    AppRuntimeConfig.instance.applyFromSettings(_settings);
    AliceInspector.syncWithRuntimeConfig();
    await _syncOfflineCashPins();
  }

  Future<void> _persistToDisk(String kioskKey) async {
    final s = _settings;
    if (s == null) return;
    await _diskCache.writeJson(_diskKey(kioskKey), appSettingsToCacheJson(s));
  }

  Future<void> _syncOfflineCashPins() async {
    await OfflineOperatorPinStore.syncServerPins(_settings?.offlineCashPins);
  }
}
