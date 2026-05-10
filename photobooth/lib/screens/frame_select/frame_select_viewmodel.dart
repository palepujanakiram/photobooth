import 'package:flutter/foundation.dart';

import '../../models/kiosk_frame_model.dart';
import '../../services/api_service.dart';
import '../../services/session_manager.dart';
import '../../utils/exceptions.dart';

class FrameSelectViewModel extends ChangeNotifier {
  FrameSelectViewModel({
    ApiService? apiService,
    SessionManager? sessionManager,
  })  : _apiService = apiService ?? ApiService(),
        _sessionManager = sessionManager ?? SessionManager();

  final ApiService _apiService;
  final SessionManager _sessionManager;

  List<KioskFrameModel> _frames = [];
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  List<KioskFrameModel> get frames => List.unmodifiable(_frames);
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get errorMessage => _errorMessage;

  Future<bool> loadFrames() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _frames = await _apiService.getKioskFrames();
      return true;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      _frames = [];
      return false;
    } catch (e) {
      _errorMessage = e.toString();
      _frames = [];
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Persists `selectedFrameId` (JSON `null` clears / defers to generation when
  /// [selectedFrameId] is null and [includeSelectedFrameId] is true).
  Future<bool> patchSelectedFrameAndSyncSession({
    required bool includeSelectedFrameId,
    String? selectedFrameId,
  }) async {
    final sessionId = _sessionManager.sessionId;
    if (sessionId == null) {
      _errorMessage = 'No active session.';
      notifyListeners();
      return false;
    }
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _apiService.updateSession(
        sessionId: sessionId,
        includeSelectedFrameId: includeSelectedFrameId,
        selectedFrameId: selectedFrameId,
      );
      _sessionManager.setSessionFromResponse(response);
      return true;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      return false;
    } catch (e) {
      _errorMessage = e.toString();
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }
}
