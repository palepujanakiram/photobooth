import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../services/api_service.dart';
import '../../services/session_manager.dart';
import '../../utils/error_reporting_helpers.dart';
import '../../utils/exceptions.dart';

class TransformationDetailsViewModel extends ChangeNotifier {
  TransformationDetailsViewModel({
    required this.runId,
    ApiService? apiService,
    SessionManager? sessionManager,
  })  : _apiService = apiService ?? ApiService(),
        _sessionManager = sessionManager ?? SessionManager();

  final String runId;
  final ApiService _apiService;
  final SessionManager _sessionManager;

  /// Active kiosk session when the API omits `run.sessionId`.
  String? get activeSessionId => _sessionManager.sessionId;

  bool _loading = true;
  String? _errorMessage;
  Map<String, dynamic>? _payload;

  bool get isLoading => _loading;
  String? get errorMessage => _errorMessage;
  Map<String, dynamic>? get payload => _payload;

  Future<void> load() async {
    _loading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _payload = await _apiService.fetchGenerationRun(runId);
    } on ApiException catch (e) {
      _errorMessage = e.userFacingMessage;
      _payload = null;
    } catch (e, st) {
      _errorMessage = e.toString();
      _payload = null;
      unawaited(
        reportIssue(
          'Failed to load generation run details',
          e,
          st,
          extraInfo: {'source': 'transformation_details', 'runId': runId},
        ),
      );
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
