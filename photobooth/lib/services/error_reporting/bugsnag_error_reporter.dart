import 'package:bugsnag_flutter/bugsnag_flutter.dart';
import 'package:flutter/foundation.dart';
import 'error_reporting_service.dart';

/// Bugsnag implementation of ErrorReportingService
class BugsnagErrorReporter implements ErrorReportingService {
  bool _isEnabled = true;

  @override
  Future<void> initialize() async {
    try {
      // Bugsnag is initialized in main.dart with bugsnag.start()
      // This method is called after start() to confirm initialization
      if (kDebugMode) {
        print('Bugsnag error reporter initialized (enabled: $_isEnabled)');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to initialize Bugsnag: $e');
      }
    }
  }

  @override
  void log(String message) {
    if (!_isEnabled) return;
    
    try {
      bugsnag.leaveBreadcrumb(message);
    } catch (e) {
      if (kDebugMode) {
        print('Failed to log breadcrumb to Bugsnag: $e');
      }
    }
  }

  @override
  Future<void> recordError(
    dynamic exception,
    StackTrace? stackTrace, {
    String? reason,
    Map<String, dynamic>? extraInfo,
    bool fatal = false,
  }) async {
    if (!_isEnabled) return;
    
    try {
      await bugsnag.notify(
        exception,
        stackTrace,
        callback: (event) {
          // Set context (reason)
          if (reason != null) {
            event.context = reason;
          }
          
          // Add extra info as metadata
          if (extraInfo != null) {
            // Convert Map<String, dynamic> to Map<String, Object>
            final metadata = extraInfo.map((key, value) => 
              MapEntry(key, value as Object? ?? 'null'));
            event.addMetadata('extra', metadata);
          }
          
          // Note: Bugsnag severity is managed automatically
          // fatal flag is for information only in metadata
          if (fatal) {
            event.addMetadata('error_details', {'fatal': true});
          }
          
          return true;
        },
      );
    } catch (e) {
      if (kDebugMode) {
        print('Failed to record error to Bugsnag: $e');
      }
    }
  }

  @override
  Future<void> setUserId(String userId) async {
    if (!_isEnabled) return;
    
    try {
      bugsnag.setUser(id: userId);
    } catch (e) {
      if (kDebugMode) {
        print('Failed to set user ID in Bugsnag: $e');
      }
    }
  }

  @override
  Future<void> setCustomKey(String key, dynamic value) async {
    if (!_isEnabled) return;
    
    try {
      bugsnag.addMetadata('custom', {key: value});
    } catch (e) {
      if (kDebugMode) {
        print('Failed to set custom key in Bugsnag: $e');
      }
    }
  }

  @override
  Future<void> setCustomKeys(Map<String, dynamic> keys) async {
    if (!_isEnabled) return;
    
    try {
      // Convert Map<String, dynamic> to Map<String, Object>
      final metadata = keys.map((key, value) => 
        MapEntry(key, value as Object? ?? 'null'));
      bugsnag.addMetadata('custom', metadata);
    } catch (e) {
      if (kDebugMode) {
        print('Failed to set custom keys in Bugsnag: $e');
      }
    }
  }

  @override
  Future<void> clearContext() async {
    if (!_isEnabled) return;
    
    try {
      // Bugsnag doesn't have a direct clear method,
      // so we clear the custom metadata section
      bugsnag.clearMetadata('custom');
    } catch (e) {
      if (kDebugMode) {
        print('Failed to clear Bugsnag context: $e');
      }
    }
  }

  @override
  bool get isEnabled => _isEnabled;

  @override
  Future<void> setEnabled(bool enabled) async {
    _isEnabled = enabled;
    // Note: Bugsnag doesn't have a runtime enable/disable method
    // We control it through the _isEnabled flag
    if (kDebugMode) {
      print('Bugsnag collection ${enabled ? "enabled" : "disabled"}');
    }
  }
}
