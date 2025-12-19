import 'package:flutter/foundation.dart';
import '../../services/api_service.dart';
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

  /// Submits the terms acceptance
  Future<bool> acceptTerms(String deviceType) async {
    if (!_isAgreed) {
      _errorMessage = 'Please agree to the Terms and Conditions';
      notifyListeners();
      return false;
    }

    if (_kioskName.trim().isEmpty) {
      _errorMessage = 'Please enter a KIOSK name';
      notifyListeners();
      return false;
    }

    _isSubmitting = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _apiService.acceptTerms(deviceType: deviceType);
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
}

