import 'package:flutter/foundation.dart';
import '../models/app_settings_model.dart';
import '../utils/app_runtime_config.dart';
import '../utils/constants.dart';
import '../utils/logger.dart';
import 'alice_inspector.dart';
import 'api_service.dart';
import 'kiosk_manager.dart';

class AppSettingsManager extends ChangeNotifier {
  final ApiService _apiService;
  final Future<String?> Function() _resolveKioskCode;

  AppSettingsManager({
    ApiService? apiService,
    @visibleForTesting Future<String?> Function()? resolveKioskCode,
  })  : _apiService = apiService ?? ApiService(),
        _resolveKioskCode =
            resolveKioskCode ?? (() => KioskManager().getKioskCode());

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

  Future<void> fetchSettings({bool forceRefresh = false}) async {
    final kioskKey = await _currentKioskKey();
    final kioskChanged =
        _settings != null && _settingsKioskKey != null && _settingsKioskKey != kioskKey;

    // Startup often loads settings before splash binds a kiosk. When the bound
    // kiosk changes, ignore the account-default cache so guest prices refresh.
    if (!forceRefresh && !kioskChanged && _settings != null) {
      // Keep [AppRuntimeConfig] in sync when callers reuse cached settings.
      AppRuntimeConfig.instance.applyFromSettings(_settings);
      return;
    }

    // If a request is already in-flight, reuse it to avoid stacking calls on
    // flaky networks / rapid lifecycle changes.
    //
    // If caller explicitly forces refresh (or kiosk changed), allow starting a
    // new request even if a non-forced fetch is in flight.
    if (!forceRefresh && !kioskChanged && _inflightFetch != null) {
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
        applyFlutterImageCacheLimits();
        AliceInspector.syncWithRuntimeConfig();
      } catch (e, st) {
        _errorMessage = e.toString();
        AppLogger.error(
          'Failed to fetch app settings',
          error: e,
          stackTrace: st,
        );
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
}
