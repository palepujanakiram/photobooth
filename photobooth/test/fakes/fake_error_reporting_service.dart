import 'package:photobooth/services/error_reporting/error_reporting_service.dart';

class FakeErrorReportingService implements ErrorReportingService {
  final List<String> logs = [];
  final List<Object> errors = [];

  @override
  Future<void> initialize() async {}

  @override
  void log(String message) => logs.add(message);

  @override
  Future<void> recordError(
    dynamic exception,
    StackTrace? stackTrace, {
    String? reason,
    Map<String, dynamic>? extraInfo,
    bool fatal = false,
  }) async {
    errors.add(exception);
  }

  @override
  Future<void> setUserId(String userId) async {}

  @override
  Future<void> setCustomKey(String key, dynamic value) async {}

  @override
  Future<void> setCustomKeys(Map<String, dynamic> keys) async {}

  @override
  Future<void> clearContext() async {}

  @override
  Future<void> setEnabled(bool enabled) async {}

  @override
  bool get isEnabled => true;
}
