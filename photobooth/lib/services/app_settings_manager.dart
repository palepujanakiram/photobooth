import 'package:flutter/foundation.dart';
import '../models/app_settings_model.dart';
import '../utils/app_runtime_config.dart';
import '../utils/constants.dart';
import '../utils/logger.dart';
import 'alice_inspector.dart';
import 'api_service.dart';

class AppSettingsManager extends ChangeNotifier {
  final ApiService _apiService;

  AppSettingsManager({ApiService? apiService})
      : _apiService = apiService ?? ApiService();

  AppSettingsModel? _settings;
  bool _isLoading = false;
  String? _errorMessage;
  DateTime? _lastFetchedAt;
  Future<void>? _inflightFetch;

  AppSettingsModel? get settings => _settings;
  bool get hasSettings => _settings != null;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  DateTime? get lastFetchedAt => _lastFetchedAt;

  /// `/api/settings` → `parallelImageCount`, clamped. Drives POST vs parallel SSE in [ApiService.generateImages].
  int resolveParallelImageCount() {
    final raw = _settings?.parallelImageCount;
    final base = (raw != null && raw > 0)
        ? raw
        : AppConstants.kAiParallelGenerationCount;
    return base.clamp(1, AppConstants.kMaxParallelImageSlots);
  }

  Future<void> fetchSettings({bool forceRefresh = false}) async {
    if (!forceRefresh && _settings != null) {
      // Keep [AppRuntimeConfig] in sync when callers reuse cached settings.
      AppRuntimeConfig.instance.applyFromSettings(_settings);
      return;
    }

    // If a request is already in-flight, reuse it to avoid stacking calls on
    // flaky networks / rapid lifecycle changes.
    //
    // If caller explicitly forces refresh, allow starting a new request even if
    // a non-forced fetch is in flight (last write wins; endpoint is idempotent).
    if (!forceRefresh && _inflightFetch != null) {
      return _inflightFetch!;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final f = () async {
      try {
        final response = await _apiService.getAppSettings();
        _settings = response;
        _lastFetchedAt = DateTime.now();
        _errorMessage = null;
        AppRuntimeConfig.instance.applyFromSettings(_settings);
        applyFlutterImageCacheLimits();
        AliceInspector.syncWithRuntimeConfig();
      } catch (e) {
        _errorMessage = e.toString();
        AppLogger.error('Failed to fetch app settings: $e');
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
