import 'error_reporting_service.dart';
import 'crashlytics_error_reporter.dart';
import 'bugsnag_error_reporter.dart';
import '../../utils/constants.dart';

/// Central manager for error reporting
/// This is the main interface that the app code should use for logging and error reporting
/// 
/// Benefits:
/// - Single point of control for all error reporting
/// - Can enable/disable reporting globally
/// - Can add multiple error reporting services (Crashlytics, Bugsnag, Sentry, etc.)
/// - Easy to switch or add new error reporting tools
/// 
/// Usage:
/// ```dart
/// // Initialize once in main.dart
/// await ErrorReportingManager.initialize();
/// 
/// // Use throughout the app
/// ErrorReportingManager.log('User logged in');
/// ErrorReportingManager.recordError(exception, stackTrace);
/// ErrorReportingManager.setCustomKey('user_type', 'premium');
/// 
/// // Enable/disable reporting
/// await ErrorReportingManager.setEnabled(false);
/// ```
class ErrorReportingManager {
  static final List<ErrorReportingService> _services = [];
  static bool _isInitialized = false;
  static bool _isEnabled = true;

  /// Private constructor to prevent instantiation
  ErrorReportingManager._();

  /// Initialize all error reporting services
  /// Call this once in main.dart before runApp()
  /// 
  /// Parameters:
  /// - [enableCrashlytics]: Whether to enable Crashlytics service (default: true)
  /// - [enableBugsnag]: Whether to enable Bugsnag service (default: true)
  /// - [enabled]: Whether error reporting should be active initially (default: true)
  ///   This can be controlled by user preferences/consent
  static Future<void> initialize({
    bool enableCrashlytics = true,
    bool enableBugsnag = true,  // Enabled by default
    bool enabled = true,
    // Add more parameters for other services as needed
    // bool enableSentry = false,
  }) async {
    if (_isInitialized) return;
    
    // Set initial enabled state
    _isEnabled = enabled;

    // Add Crashlytics if enabled
    if (enableCrashlytics) {
      _services.add(CrashlyticsErrorReporter());
    }

    // Add Bugsnag if enabled
    if (enableBugsnag) {
      _services.add(BugsnagErrorReporter());
    }

    // Add more services here in the future
    // if (enableSentry) {
    //   _services.add(SentryErrorReporter());
    // }

    // Initialize all services
    for (final service in _services) {
      await service.initialize();
    }

    _isInitialized = true;
  }

  /// Log a message/breadcrumb
  /// This creates a trail of events that help understand what led to an error
  static void log(String message) {
    if (!_isEnabled || !AppConstants.kEnableLogOutput) return;

    for (final service in _services) {
      service.log(message);
    }
  }

  /// Record a non-fatal error with optional context
  /// 
  /// Parameters:
  /// - exception: The exception/error to record
  /// - stackTrace: Stack trace (optional)
  /// - reason: Human-readable reason for the error
  /// - extraInfo: Additional context as key-value pairs
  /// - fatal: Whether this is a fatal error (default: false)
  static Future<void> recordError(
    dynamic exception,
    StackTrace? stackTrace, {
    String? reason,
    Map<String, dynamic>? extraInfo,
    bool fatal = false,
  }) async {
    if (!_isEnabled) return;

    for (final service in _services) {
      await service.recordError(
        exception,
        stackTrace,
        reason: reason,
        extraInfo: extraInfo,
        fatal: fatal,
      );
    }
  }

  /// Set user identifier for error reports
  /// Useful for tracking which users are experiencing issues
  static Future<void> setUserId(String userId) async {
    if (!_isEnabled) return;

    for (final service in _services) {
      await service.setUserId(userId);
    }
  }

  /// Set a single custom key-value pair
  /// This context will be attached to all future error reports
  static Future<void> setCustomKey(String key, dynamic value) async {
    if (!_isEnabled) return;

    for (final service in _services) {
      await service.setCustomKey(key, value);
    }
  }

  /// Set multiple custom key-value pairs at once
  /// This is more efficient than calling setCustomKey multiple times
  static Future<void> setCustomKeys(Map<String, dynamic> keys) async {
    if (!_isEnabled) return;

    for (final service in _services) {
      await service.setCustomKeys(keys);
    }
  }

  /// Clear all custom context
  /// Useful when starting a new session or logging out a user
  static Future<void> clearContext() async {
    if (!_isEnabled) return;

    for (final service in _services) {
      await service.clearContext();
    }
  }

  /// Check if error reporting is enabled
  static bool get isEnabled => _isEnabled;

  /// Enable or disable all error reporting
  /// When disabled, all log() and recordError() calls will be no-ops
  /// This is useful for:
  /// - Respecting user privacy preferences
  /// - Debugging without sending data
  /// - Complying with regulations (GDPR, etc.)
  static Future<void> setEnabled(bool enabled) async {
    _isEnabled = enabled;

    for (final service in _services) {
      await service.setEnabled(enabled);
    }
  }

  /// Convenience method to set camera context
  /// Sets camera-related keys for better error debugging
  static Future<void> setCameraContext({
    String? cameraId,
    String? cameraDirection,
    bool? isExternal,
  }) async {
    final context = <String, dynamic>{};
    if (cameraId != null) context['camera_id'] = cameraId;
    if (cameraDirection != null) context['camera_direction'] = cameraDirection;
    if (isExternal != null) context['is_external_camera'] = isExternal;
    
    if (context.isNotEmpty) {
      await setCustomKeys(context);
    }
  }

  /// Convenience method to set photo capture context
  /// Sets photo-related keys for better error debugging
  static Future<void> setPhotoCaptureContext({
    String? photoId,
    String? sessionId,
    String? themeId,
  }) async {
    final context = <String, dynamic>{};
    if (photoId != null) context['photo_id'] = photoId;
    if (sessionId != null) context['session_id'] = sessionId;
    if (themeId != null) context['theme_id'] = themeId;
    
    if (context.isNotEmpty) {
      await setCustomKeys(context);
    }
  }

  /// Get the number of active error reporting services
  static int get serviceCount => _services.length;

  /// Check if the manager has been initialized
  static bool get isInitialized => _isInitialized;
}
