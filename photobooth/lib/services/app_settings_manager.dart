import 'package:flutter/foundation.dart';
import '../models/app_settings_model.dart';
import '../utils/app_runtime_config.dart';
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

  AppSettingsModel? get settings => _settings;
  bool get hasSettings => _settings != null;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  DateTime? get lastFetchedAt => _lastFetchedAt;

  Future<void> fetchSettings({bool forceRefresh = false}) async {
    if (_isLoading) {
      return;
    }
    if (!forceRefresh && _settings != null) {
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

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
  }
}
