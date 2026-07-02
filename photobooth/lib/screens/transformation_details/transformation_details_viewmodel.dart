import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../services/api_service.dart';
import '../../utils/error_reporting_helpers.dart';
import '../../utils/exceptions.dart';

class TransformationDetailsViewModel extends ChangeNotifier {
  TransformationDetailsViewModel({
    required this.runId,
    ApiService? apiService,
  }) : _apiService = apiService ?? ApiService();

  final String runId;
  final ApiService _apiService;

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
