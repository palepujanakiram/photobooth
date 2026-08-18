import 'package:flutter/foundation.dart';

import '../../services/api_service.dart';
import '../../services/kiosk_manager.dart';
import '../../services/session_manager.dart';
import '../../utils/exceptions.dart';
import '../../utils/logger.dart';

/// Creates a guest session then the Capture station navigates to the camera.
class EventCaptureStationViewModel extends ChangeNotifier {
  EventCaptureStationViewModel({
    ApiService? apiService,
    SessionManager? sessionManager,
    KioskManager? kioskManager,
  })  : _api = apiService ?? ApiService(),
        _session = sessionManager ?? SessionManager(),
        _kiosk = kioskManager ?? KioskManager();

  final ApiService _api;
  final SessionManager _session;
  final KioskManager _kiosk;

  bool _busy = false;
  String? _error;

  bool get isBusy => _busy;
  String? get errorMessage => _error;
  bool get hasError => _error != null;

  Future<bool> startNextGuest() async {
    if (_busy) return false;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final kioskCode = await _kiosk.getKioskCode();
      final response = await _api.acceptTermsAndCreateSession(
        kioskCode: kioskCode,
        source: 'event-capture',
        groupConsentAccepted: true,
      );
      _session.setSessionFromResponse(response);
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      return false;
    } catch (e, st) {
      AppLogger.error('Event capture start failed', error: e, stackTrace: st);
      _error = 'Could not start a new guest session.';
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
