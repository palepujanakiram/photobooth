/// Abstract interface for error reporting services
/// Implement this interface to add support for different error reporting tools
/// (e.g., Crashlytics, Bugsnag, Sentry, etc.)
abstract class ErrorReportingService {
  /// Initialize the error reporting service
  Future<void> initialize();

  /// Log a message/breadcrumb
  void log(String message);

  /// Record a non-fatal error
  Future<void> recordError(
    dynamic exception,
    StackTrace? stackTrace, {
    String? reason,
    Map<String, dynamic>? extraInfo,
    bool fatal = false,
  });

  /// Set user identifier
  Future<void> setUserId(String userId);

  /// Set custom key-value pairs
  Future<void> setCustomKey(String key, dynamic value);

  /// Set multiple custom keys at once
  Future<void> setCustomKeys(Map<String, dynamic> keys);

  /// Clear custom context
  Future<void> clearContext();

  /// Check if service is enabled
  bool get isEnabled;

  /// Enable/disable the service
  Future<void> setEnabled(bool enabled);
}
