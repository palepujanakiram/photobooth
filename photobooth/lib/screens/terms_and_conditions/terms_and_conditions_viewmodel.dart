import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../services/api_service.dart';
import '../../services/kiosk_manager.dart';
import '../../services/session_manager.dart';
import '../../services/file_helper.dart';
import '../../utils/exceptions.dart';

class TermsAndConditionsViewModel extends ChangeNotifier {
  final ApiService _apiService;
  final KioskManager _kioskManager;
  bool _isAgreed = false;
  bool _isSubmitting = false;
  String? _errorMessage;
  String _kioskName = '';
  String? _kioskCode;
  bool _kioskCodeLoaded = false;
  
  // Timer tracking
  Timer? _timer;
  int _elapsedSeconds = 0;

  TermsAndConditionsViewModel({
    ApiService? apiService,
    KioskManager? kioskManager,
  })  : _apiService = apiService ?? ApiService(),
        _kioskManager = kioskManager ?? KioskManager() {
    unawaited(_loadKioskCode());
  }

  bool get isAgreed => _isAgreed;
  bool get isSubmitting => _isSubmitting;
  String? get errorMessage => _errorMessage;
  bool get hasError => _errorMessage != null;
  String get kioskName => _kioskName;
  String? get kioskCode => _kioskCode;
  bool get kioskCodeLoaded => _kioskCodeLoaded;
  bool get canSubmit => _isAgreed && !_isSubmitting;
  int get elapsedSeconds => _elapsedSeconds;

  Future<void> _loadKioskCode() async {
    try {
      _kioskCode = await _kioskManager.getKioskCode();
      _kioskCodeLoaded = true;
      notifyListeners();
    } catch (_) {
      _kioskCodeLoaded = true;
      notifyListeners();
    }
  }

  /// Reload kiosk code from storage (e.g. after returning from splash kiosk management).
  Future<void> reloadKioskFromStorage() async {
    _errorMessage = null;
    try {
      _kioskCode = await _kioskManager.getKioskCode();
      notifyListeners();
    } catch (_) {
      notifyListeners();
    }
  }

  void _startTimer() {
    _elapsedSeconds = 0;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _elapsedSeconds++;
      notifyListeners();
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _stopTimer();
    super.dispose();
  }

  /// Toggles the agreement checkbox
  void toggleAgreement(bool value) {
    _isAgreed = value;
    _errorMessage = null;
    notifyListeners();
  }

  /// Updates the KIOSK name
  void updateKioskName(String name) {
    _kioskName = name;
    _errorMessage = null;
    notifyListeners();
  }

  /// Updates kiosk code (persisted, optional).
  Future<void> updateKioskCode(String? code) async {
    final trimmed = code?.trim();
    _kioskCode =
        (trimmed == null || trimmed.isEmpty) ? null : trimmed.toUpperCase();
    _errorMessage = null;
    notifyListeners();
    try {
      await _kioskManager.setKioskCode(_kioskCode);
    } catch (_) {}
  }

  /// Validates [code] against the backend before persisting it.
  /// Returns true when valid and saved.
  Future<bool> validateAndSetKioskCode(String code) async {
    final normalized = code.trim().toUpperCase();
    if (normalized.isEmpty) {
      _errorMessage = 'Please enter a kiosk code';
      notifyListeners();
      return false;
    }
    _errorMessage = null;
    notifyListeners();
    final ok = await _apiService.validateKioskCode(normalized);
    if (!ok) {
      _errorMessage = 'Invalid kiosk code. Please check and try again.';
      notifyListeners();
      return false;
    }
    await updateKioskCode(normalized);
    return true;
  }

  /// Submits the terms acceptance and creates a session
  Future<bool> acceptTermsAndCreateSession(String? kioskCode) async {
    if (!_isAgreed) {
      _errorMessage = 'Please agree to the Terms and Conditions';
      notifyListeners();
      return false;
    }

    // Fire-and-forget cleanup of temp images
    FileHelper.cleanupTempImages();

    _isSubmitting = true;
    _errorMessage = null;
    _startTimer();
    notifyListeners();

    try {
      const createSessionTimeout = Duration(seconds: 30);
      final response = await _apiService.acceptTermsAndCreateSession(
        kioskCode: kioskCode,
        source: kIsWeb ? 'web' : 'mobile',
      ).timeout(
        createSessionTimeout,
        onTimeout: () => throw TimeoutException(
          'Creating session timed out after ${createSessionTimeout.inSeconds} seconds',
        ),
      );
      
      // Store session data in SessionManager from API response
      final sessionManager = SessionManager();
      sessionManager.setSessionFromResponse(response);
      
      return true;
    } on TimeoutException {
      _errorMessage = 'Request took too long. Please check your connection and try again.';
      return false;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      return false;
    } catch (e) {
      _errorMessage = 'Failed to accept terms: $e';
      return false;
    } finally {
      _stopTimer();
      _isSubmitting = false;
      notifyListeners();
    }
  }

  /// Legacy method for backward compatibility
  Future<bool> acceptTerms(String deviceType) async {
    return acceptTermsAndCreateSession(null);
  }
}

