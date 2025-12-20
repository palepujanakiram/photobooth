import 'package:flutter/foundation.dart';
import '../../services/api_service.dart';
import '../../services/session_manager.dart';
import '../../utils/exceptions.dart';

class TermsAndConditionsViewModel extends ChangeNotifier {
  final ApiService _apiService;
  bool _isAgreed = false;
  bool _isSubmitting = false;
  String? _errorMessage;
  String _kioskName = '';

  TermsAndConditionsViewModel({ApiService? apiService})
      : _apiService = apiService ?? ApiService();

  bool get isAgreed => _isAgreed;
  bool get isSubmitting => _isSubmitting;
  String? get errorMessage => _errorMessage;
  bool get hasError => _errorMessage != null;
  String get kioskName => _kioskName;
  bool get canSubmit => _isAgreed && !_isSubmitting && _kioskName.trim().isNotEmpty;

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

  /// Submits the terms acceptance and creates a session
  Future<bool> acceptTermsAndCreateSession(String? kioskCode) async {
    if (!_isAgreed) {
      _errorMessage = 'Please agree to the Terms and Conditions';
      notifyListeners();
      return false;
    }

    _isSubmitting = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _apiService.acceptTermsAndCreateSession(
        kioskCode: kioskCode,
      );
      
      // Store session data in SessionManager from API response
      final sessionManager = SessionManager();
      sessionManager.setSessionFromResponse(response);
      
      return true;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'Failed to accept terms: $e';
      notifyListeners();
      return false;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  /// Legacy method for backward compatibility
  Future<bool> acceptTerms(String deviceType) async {
    return acceptTermsAndCreateSession(null);
  }
}

