import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'error_reporting_service.dart';

/// Crashlytics implementation of ErrorReportingService
class CrashlyticsErrorReporter implements ErrorReportingService {
  final FirebaseCrashlytics _crashlytics = FirebaseCrashlytics.instance;
  bool _isEnabled = true;

  @override
  Future<void> initialize() async {
    try {
      await _crashlytics.setCrashlyticsCollectionEnabled(_isEnabled);
      if (kDebugMode) {
        print('Crashlytics initialized (enabled: $_isEnabled)');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to initialize Crashlytics: $e');
      }
    }
  }

  @override
  void log(String message) {
    if (!_isEnabled) return;
    
    try {
      _crashlytics.log(message);
    } catch (e) {
      if (kDebugMode) {
        print('Failed to log to Crashlytics: $e');
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
      // Convert extraInfo to List<Object> if provided
      if (extraInfo != null) {
        final information = extraInfo.entries
            .map((e) => '${e.key}: ${e.value}')
            .toList();
        
        await _crashlytics.recordError(
          exception,
          stackTrace,
          reason: reason,
          information: information,
          fatal: fatal,
        );
      } else {
        await _crashlytics.recordError(
          exception,
          stackTrace,
          reason: reason,
          fatal: fatal,
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to record error to Crashlytics: $e');
      }
    }
  }

  @override
  Future<void> setUserId(String userId) async {
    if (!_isEnabled) return;
    
    try {
      await _crashlytics.setUserIdentifier(userId);
    } catch (e) {
      if (kDebugMode) {
        print('Failed to set user ID in Crashlytics: $e');
      }
    }
  }

  @override
  Future<void> setCustomKey(String key, dynamic value) async {
    if (!_isEnabled) return;
    
    try {
      await _crashlytics.setCustomKey(key, value);
    } catch (e) {
      if (kDebugMode) {
        print('Failed to set custom key in Crashlytics: $e');
      }
    }
  }

  @override
  Future<void> setCustomKeys(Map<String, dynamic> keys) async {
    if (!_isEnabled) return;
    
    for (final entry in keys.entries) {
      await setCustomKey(entry.key, entry.value);
    }
  }

  @override
  Future<void> clearContext() async {
    if (!_isEnabled) return;
    
    try {
      // Firebase Crashlytics doesn't have a clear method,
      // so we set empty strings for common keys
      await setCustomKeys({
        'camera_id': '',
        'camera_direction': '',
        'is_external_camera': false,
        'photo_id': '',
        'session_id': '',
        'theme_id': '',
        'user_id': '',
      });
    } catch (e) {
      if (kDebugMode) {
        print('Failed to clear Crashlytics context: $e');
      }
    }
  }

  @override
  bool get isEnabled => _isEnabled;

  @override
  Future<void> setEnabled(bool enabled) async {
    _isEnabled = enabled;
    try {
      await _crashlytics.setCrashlyticsCollectionEnabled(enabled);
      if (kDebugMode) {
        print('Crashlytics collection ${enabled ? "enabled" : "disabled"}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to set Crashlytics enabled state: $e');
      }
    }
  }
}
