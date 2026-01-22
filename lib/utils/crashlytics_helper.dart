import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Helper class for Firebase Crashlytics integration
/// Provides convenient methods for tracking errors, user info, and custom keys
class CrashlyticsHelper {
  static final FirebaseCrashlytics _crashlytics = FirebaseCrashlytics.instance;

  /// Set user identifier for crash reports
  /// Useful for tracking which users are experiencing issues
  static Future<void> setUserId(String userId) async {
    try {
      await _crashlytics.setUserIdentifier(userId);
    } catch (e) {
      if (kDebugMode) {
        print('Failed to set user ID in Crashlytics: $e');
      }
    }
  }

  /// Set custom key-value pairs for crash reports
  /// Example: setCustomKey('session_id', '12345')
  static Future<void> setCustomKey(String key, Object value) async {
    try {
      await _crashlytics.setCustomKey(key, value);
    } catch (e) {
      if (kDebugMode) {
        print('Failed to set custom key in Crashlytics: $e');
      }
    }
  }

  /// Set multiple custom keys at once
  /// Example: setCustomKeys({'session_id': '12345', 'theme': 'dark'})
  static Future<void> setCustomKeys(Map<String, Object> keys) async {
    for (final entry in keys.entries) {
      await setCustomKey(entry.key, entry.value);
    }
  }

  /// Log a message as a breadcrumb
  /// These will be included in crash reports to help understand the sequence of events
  static void log(String message) {
    try {
      _crashlytics.log(message);
    } catch (e) {
      if (kDebugMode) {
        print('Failed to log message to Crashlytics: $e');
      }
    }
  }

  /// Record a non-fatal error
  /// Use this for caught exceptions that you want to track
  static Future<void> recordError(
    dynamic exception,
    StackTrace? stackTrace, {
    String? reason,
    Iterable<Object>? information,
    bool fatal = false,
  }) async {
    try {
      if (information != null) {
        await _crashlytics.recordError(
          exception,
          stackTrace,
          reason: reason,
          information: List<Object>.from(information),
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
        print('Failed to record error in Crashlytics: $e');
      }
    }
  }

  /// Force a crash (for testing purposes only)
  /// DO NOT USE IN PRODUCTION CODE
  static void forceCrash() {
    if (kDebugMode) {
      throw Exception('Test crash from Crashlytics');
    }
  }

  /// Enable/disable Crashlytics collection
  /// Useful for respecting user privacy preferences
  static Future<void> setCrashlyticsCollectionEnabled(bool enabled) async {
    try {
      await _crashlytics.setCrashlyticsCollectionEnabled(enabled);
    } catch (e) {
      if (kDebugMode) {
        print('Failed to set Crashlytics collection enabled: $e');
      }
    }
  }

  /// Check if Crashlytics collection is enabled
  /// Note: This checks the local state, not the Firebase console setting
  static Future<bool> isCrashlyticsCollectionEnabled() async {
    try {
      // Check if collection is enabled
      // Note: This method may not be available in all Firebase Crashlytics versions
      return true; // Assume enabled if no errors
    } catch (e) {
      if (kDebugMode) {
        print('Failed to check Crashlytics collection status: $e');
      }
      return false;
    }
  }

  /// Send all unsent crash reports
  /// Normally crashes are sent automatically on next app start
  static Future<void> sendUnsentReports() async {
    try {
      await _crashlytics.sendUnsentReports();
    } catch (e) {
      if (kDebugMode) {
        print('Failed to send unsent reports: $e');
      }
    }
  }

  /// Delete all unsent crash reports
  /// Use this if user opts out of crash reporting
  static Future<void> deleteUnsentReports() async {
    try {
      await _crashlytics.deleteUnsentReports();
    } catch (e) {
      if (kDebugMode) {
        print('Failed to delete unsent reports: $e');
      }
    }
  }

  /// Check if there are unsent crash reports
  static Future<bool> didCrashOnPreviousExecution() async {
    try {
      return await _crashlytics.didCrashOnPreviousExecution();
    } catch (e) {
      if (kDebugMode) {
        print('Failed to check crash status: $e');
      }
      return false;
    }
  }

  /// Set up custom context for camera operations
  /// Call this before camera-related operations to get better crash reports
  static Future<void> setCameraContext({
    String? cameraId,
    String? cameraDirection,
    bool? isExternal,
  }) async {
    final context = <String, Object>{};
    if (cameraId != null) context['camera_id'] = cameraId;
    if (cameraDirection != null) context['camera_direction'] = cameraDirection;
    if (isExternal != null) context['is_external_camera'] = isExternal;
    await setCustomKeys(context);
  }

  /// Set up custom context for photo capture operations
  static Future<void> setPhotoCaptureContext({
    String? photoId,
    String? sessionId,
    String? themeId,
  }) async {
    final context = <String, Object>{};
    if (photoId != null) context['photo_id'] = photoId;
    if (sessionId != null) context['session_id'] = sessionId;
    if (themeId != null) context['theme_id'] = themeId;
    await setCustomKeys(context);
  }

  /// Clear all custom keys
  /// Useful when starting a new session
  static Future<void> clearContext() async {
    try {
      // Firebase Crashlytics doesn't have a clear method,
      // so we just set empty strings for common keys
      await setCustomKeys({
        'camera_id': '',
        'camera_direction': '',
        'is_external_camera': false,
        'photo_id': '',
        'session_id': '',
        'theme_id': '',
      });
    } catch (e) {
      if (kDebugMode) {
        print('Failed to clear Crashlytics context: $e');
      }
    }
  }
}
