import 'package:flutter/foundation.dart';

import '../../services/api_service.dart';
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
    } catch (e) {
      _errorMessage = e.toString();
      _payload = null;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
